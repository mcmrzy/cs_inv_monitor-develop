// Package apkmeta 从 Android APK 中读取版本与 SDK 元数据。
//
// 安装包元数据以 APK 本体为唯一权威来源：管理后台上传 APK 后由服务端解析
// AndroidManifest.xml，避免人工填写版本号、包名导致与安装包不一致。
package apkmeta

import (
	"archive/zip"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"
	"unicode/utf16"
)

// Metadata 是从 APK 中解析出的标识信息。
type Metadata struct {
	PackageName string
	VersionName string
	VersionCode int64
	MinSDK      int
	TargetSDK   int
}

// AndroidManifest.xml 压缩后通常只有几 KB；限制上限防止解压炸弹。
const maxManifestSize = 8 << 20

// Android 资源 ID。属性优先按资源 ID 匹配，name 字符串只作为兼容回退。
const (
	attrVersionCode = 0x0101021b
	attrVersionName = 0x0101021c
	attrMinSDK      = 0x0101020c
	attrTargetSDK   = 0x01010270
)

// AXML 块类型。
const (
	chunkTypeStringPool   = 0x0001
	chunkTypeXML          = 0x0003
	chunkTypeResourceMap  = 0x0180
	chunkTypeStartElement = 0x0102
	chunkTypeEndElement   = 0x0103
)

// AXML 类型化值的 dataType。
const (
	typeString     = 0x03
	typeIntDec     = 0x10
	typeIntHex     = 0x11
	typeIntBoolean = 0x12
)

const noIndex = 0xFFFFFFFF

// FromAPK 读取 APK 中的 AndroidManifest.xml 并解析元数据。
func FromAPK(r io.ReaderAt, size int64) (*Metadata, error) {
	zr, err := zip.NewReader(r, size)
	if err != nil {
		return nil, fmt.Errorf("解析 APK 压缩包失败: %w", err)
	}
	var manifest *zip.File
	for _, f := range zr.File {
		if f.Name == "AndroidManifest.xml" {
			manifest = f
			break
		}
	}
	if manifest == nil {
		return nil, errors.New("APK 中缺少 AndroidManifest.xml，可能不是有效的安装包")
	}
	if manifest.UncompressedSize64 > maxManifestSize {
		return nil, errors.New("AndroidManifest.xml 体积异常，拒绝解析")
	}
	rc, err := manifest.Open()
	if err != nil {
		return nil, fmt.Errorf("读取 AndroidManifest.xml 失败: %w", err)
	}
	defer rc.Close()

	data, err := io.ReadAll(io.LimitReader(rc, maxManifestSize))
	if err != nil {
		return nil, fmt.Errorf("读取 AndroidManifest.xml 失败: %w", err)
	}
	return FromManifest(data)
}

// FromManifest 解析二进制 AndroidManifest.xml（AXML）。
func FromManifest(data []byte) (*Metadata, error) {
	if len(data) < 8 {
		return nil, errors.New("AndroidManifest.xml 数据过短")
	}
	if binary.LittleEndian.Uint16(data) != chunkTypeXML {
		return nil, errors.New("AndroidManifest.xml 不是二进制 XML 格式")
	}
	headerSize := int(binary.LittleEndian.Uint16(data[2:4]))
	if headerSize < 8 {
		headerSize = 8
	}
	total := int(binary.LittleEndian.Uint32(data[4:8]))
	if total <= 0 || total > len(data) {
		total = len(data)
	}

	meta := &Metadata{}
	var pool *stringPool
	var resMap []uint32
	sawManifest := false
	depth := 0

	for offset := headerSize; offset+8 <= total; {
		chunkType := binary.LittleEndian.Uint16(data[offset : offset+2])
		chunkHeaderSize := int(binary.LittleEndian.Uint16(data[offset+2 : offset+4]))
		chunkSize := int(binary.LittleEndian.Uint32(data[offset+4 : offset+8]))
		if chunkSize < 8 || offset+chunkSize > total {
			break
		}
		chunk := data[offset : offset+chunkSize]

		switch chunkType {
		case chunkTypeStringPool:
			p, err := parseStringPool(chunk)
			if err != nil {
				return nil, err
			}
			pool = p
		case chunkTypeResourceMap:
			resMap = parseResourceMap(chunk)
		case chunkTypeStartElement:
			if pool == nil {
				return nil, errors.New("AndroidManifest.xml 缺少字符串池")
			}
			if chunkHeaderSize < 16 || len(chunk) < chunkHeaderSize {
				depth++
				break
			}
			nameIdx, attrs := parseStartElement(chunk[chunkHeaderSize:], pool, resMap)
			switch {
			case sawManifest && depth == 1 && nameIdx == pool.indexOf("uses-sdk"):
				readSDKAttrs(attrs, pool, meta)
			case !sawManifest && nameIdx == pool.indexOf("manifest"):
				sawManifest = true
				readManifestAttrs(attrs, pool, meta)
			}
			depth++
		case chunkTypeEndElement:
			if depth > 0 {
				depth--
			}
		}
		offset += chunkSize
	}

	if !sawManifest {
		return nil, errors.New("AndroidManifest.xml 缺少 manifest 节点")
	}
	if meta.PackageName == "" {
		return nil, errors.New("AndroidManifest.xml 缺少 package 属性")
	}
	return meta, nil
}

func readManifestAttrs(attrs []xmlAttribute, pool *stringPool, meta *Metadata) {
	if a, ok := attrValue(attrs, 0, "package"); ok {
		meta.PackageName = strings.TrimSpace(a.stringValue(pool))
	}
	if a, ok := attrValue(attrs, attrVersionCode, "versionCode"); ok {
		if v, ok := a.intValue(pool); ok && v > 0 {
			meta.VersionCode = v
		}
	}
	if a, ok := attrValue(attrs, attrVersionName, "versionName"); ok {
		meta.VersionName = strings.TrimSpace(a.stringValue(pool))
	}
}

func readSDKAttrs(attrs []xmlAttribute, pool *stringPool, meta *Metadata) {
	if a, ok := attrValue(attrs, attrMinSDK, "minSdkVersion"); ok {
		if v, ok := a.intValue(pool); ok && v > 0 {
			meta.MinSDK = int(v)
		}
	}
	if a, ok := attrValue(attrs, attrTargetSDK, "targetSdkVersion"); ok {
		if v, ok := a.intValue(pool); ok && v > 0 {
			meta.TargetSDK = int(v)
		}
	}
}

// ===================== 属性 =====================

type xmlAttribute struct {
	nameIdx  uint32
	name     string
	dataType byte
	data     uint32
	rawValue uint32
	// resolved 是资源映射表给出的资源 ID；为 0 表示没有映射。
	resolved uint32
}

// attrValue 先按 Android 资源 ID 匹配（与命名空间无关、最可靠），
// 再回退到属性名匹配（少数工具链省略资源映射表）。
func attrValue(attrs []xmlAttribute, resID uint32, name string) (xmlAttribute, bool) {
	if resID != 0 {
		for _, a := range attrs {
			if a.resolved == resID {
				return a, true
			}
		}
	}
	for _, a := range attrs {
		if a.name == name {
			return a, true
		}
	}
	return xmlAttribute{}, false
}

func (a xmlAttribute) stringValue(pool *stringPool) string {
	if a.dataType == typeString {
		if s := pool.at(a.data); s != "" {
			return s
		}
	}
	if a.rawValue != noIndex {
		return pool.at(a.rawValue)
	}
	return ""
}

func (a xmlAttribute) intValue(pool *stringPool) (int64, bool) {
	switch a.dataType {
	case typeIntDec, typeIntHex, typeIntBoolean:
		return int64(int32(a.data)), true
	case typeString:
		text := strings.TrimSpace(a.stringValue(pool))
		v, err := strconv.ParseInt(text, 10, 64)
		if err != nil {
			// minSdkVersion 允许是预览版代号，此时无法作为整数使用。
			return 0, false
		}
		return v, true
	default:
		return 0, false
	}
}

func parseStartElement(body []byte, pool *stringPool, resMap []uint32) (uint32, []xmlAttribute) {
	if len(body) < 20 {
		return noIndex, nil
	}
	nameIdx := binary.LittleEndian.Uint32(body[4:8])
	attrStart := int(binary.LittleEndian.Uint16(body[8:10]))
	attrSize := int(binary.LittleEndian.Uint16(body[10:12]))
	attrCount := int(binary.LittleEndian.Uint16(body[12:14]))
	if attrSize < 20 || attrStart < 0 || attrCount <= 0 {
		return nameIdx, nil
	}

	attrs := make([]xmlAttribute, 0, attrCount)
	for i := 0; i < attrCount; i++ {
		start := attrStart + i*attrSize
		if start < 0 || start+20 > len(body) {
			break
		}
		raw := body[start : start+20]
		attr := xmlAttribute{
			nameIdx:  binary.LittleEndian.Uint32(raw[4:8]),
			dataType: raw[15],
			data:     binary.LittleEndian.Uint32(raw[16:20]),
			rawValue: binary.LittleEndian.Uint32(raw[8:12]),
		}
		attr.name = pool.at(attr.nameIdx)
		if int(attr.nameIdx) < len(resMap) {
			attr.resolved = resMap[attr.nameIdx]
		}
		attrs = append(attrs, attr)
	}
	return nameIdx, attrs
}

// ===================== 块解析 =====================

func parseResourceMap(chunk []byte) []uint32 {
	if len(chunk) < 8 {
		return nil
	}
	count := (len(chunk) - 8) / 4
	ids := make([]uint32, count)
	for i := 0; i < count; i++ {
		ids[i] = binary.LittleEndian.Uint32(chunk[8+i*4 : 12+i*4])
	}
	return ids
}

type stringPool struct {
	strings []string
	index   map[string]uint32
}

func (p *stringPool) at(idx uint32) string {
	if p == nil || idx == noIndex || int(idx) >= len(p.strings) {
		return ""
	}
	return p.strings[idx]
}

func (p *stringPool) indexOf(s string) uint32 {
	if p == nil {
		return noIndex
	}
	if idx, ok := p.index[s]; ok {
		return idx
	}
	return noIndex
}

func parseStringPool(chunk []byte) (*stringPool, error) {
	if len(chunk) < 28 {
		return nil, errors.New("AndroidManifest.xml 字符串池头部不完整")
	}
	count := int(binary.LittleEndian.Uint32(chunk[8:12]))
	flags := binary.LittleEndian.Uint32(chunk[16:20])
	stringsStart := int(binary.LittleEndian.Uint32(chunk[20:24]))
	if count < 0 || 28+count*4 > len(chunk) {
		return nil, errors.New("AndroidManifest.xml 字符串池索引越界")
	}
	isUTF8 := flags&(1<<8) != 0

	pool := &stringPool{
		strings: make([]string, 0, count),
		index:   make(map[string]uint32, count),
	}
	for i := 0; i < count; i++ {
		offset := int(binary.LittleEndian.Uint32(chunk[28+i*4 : 32+i*4]))
		start := stringsStart + offset
		value := ""
		if start >= 0 && start < len(chunk) {
			if decoded, err := decodePoolString(chunk[start:], isUTF8); err == nil {
				value = decoded
			}
		}
		pool.strings = append(pool.strings, value)
		if _, exists := pool.index[value]; !exists {
			pool.index[value] = uint32(i)
		}
	}
	return pool, nil
}

func decodePoolString(data []byte, isUTF8 bool) (string, error) {
	if isUTF8 {
		_, n := readLength8(data)
		if n == 0 {
			return "", errors.New("字符串长度字段不完整")
		}
		byteLen, m := readLength8(data[n:])
		if m == 0 {
			return "", errors.New("字符串字节长度字段不完整")
		}
		start := n + m
		if byteLen < 0 || start+byteLen > len(data) {
			return "", errors.New("字符串越界")
		}
		return string(data[start : start+byteLen]), nil
	}

	charLen, n := readLength16(data)
	if n == 0 {
		return "", errors.New("字符串长度字段不完整")
	}
	if charLen < 0 || n+charLen*2 > len(data) {
		return "", errors.New("字符串越界")
	}
	units := make([]uint16, charLen)
	for i := 0; i < charLen; i++ {
		units[i] = binary.LittleEndian.Uint16(data[n+i*2:])
	}
	return string(utf16.Decode(units)), nil
}

// readLength8 读取 UTF-8 字符串池的两字节变长长度（高位 0x80 表示续字节）。
func readLength8(data []byte) (int, int) {
	if len(data) == 0 {
		return 0, 0
	}
	if data[0]&0x80 != 0 {
		if len(data) < 2 {
			return 0, 0
		}
		return int(data[0]&0x7f)<<8 | int(data[1]), 2
	}
	return int(data[0]), 1
}

// readLength16 读取 UTF-16 字符串池的长度（高位 0x8000 表示双字）。
func readLength16(data []byte) (int, int) {
	if len(data) < 2 {
		return 0, 0
	}
	v := binary.LittleEndian.Uint16(data)
	if v&0x8000 != 0 {
		if len(data) < 4 {
			return 0, 0
		}
		return int(v&0x7fff)<<16 | int(binary.LittleEndian.Uint16(data[2:])), 4
	}
	return int(v), 2
}
