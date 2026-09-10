package apkmeta

import (
	"archive/zip"
	"bytes"
	"encoding/binary"
	"testing"
	"unicode/utf16"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ===================== 测试用 AXML 构造器 =====================
//
// 真实 APK 的 AndroidManifest.xml 是二进制 XML。测试直接构造该格式的字节流，
// 既验证解析器对格式细节（字符串池编码、资源映射表、属性类型）的处理，
// 又避免把二进制安装包纳入版本库。

type axmlStringPool struct {
	values []string
	index  map[string]uint32
}

func newAxmlStringPool() *axmlStringPool {
	return &axmlStringPool{index: map[string]uint32{}}
}

func (p *axmlStringPool) add(s string) uint32 {
	if idx, ok := p.index[s]; ok {
		return idx
	}
	idx := uint32(len(p.values))
	p.values = append(p.values, s)
	p.index[s] = idx
	return idx
}

func (p *axmlStringPool) encode(utf8Pool bool) []byte {
	blobs := make([][]byte, len(p.values))
	for i, s := range p.values {
		blobs[i] = encodePoolString(s, utf8Pool)
	}
	dataStart := 28 + 4*len(p.values)
	offsets := make([]byte, 4*len(p.values))
	cursor := 0
	var data bytes.Buffer
	for i, b := range blobs {
		binary.LittleEndian.PutUint32(offsets[i*4:], uint32(cursor))
		cursor += len(b)
		data.Write(b)
	}

	chunk := make([]byte, dataStart+data.Len())
	binary.LittleEndian.PutUint16(chunk[0:], chunkTypeStringPool)
	binary.LittleEndian.PutUint16(chunk[2:], 28)
	binary.LittleEndian.PutUint32(chunk[8:], uint32(len(p.values)))
	binary.LittleEndian.PutUint32(chunk[12:], 0)
	flags := uint32(0)
	if utf8Pool {
		flags = 1 << 8
	}
	binary.LittleEndian.PutUint32(chunk[16:], flags)
	binary.LittleEndian.PutUint32(chunk[20:], uint32(dataStart))
	copy(chunk[28:], offsets)
	copy(chunk[dataStart:], data.Bytes())
	return finishChunk(chunk)
}

func encodePoolString(s string, utf8Pool bool) []byte {
	var buf bytes.Buffer
	if utf8Pool {
		writeLength8(&buf, len(utf16.Encode([]rune(s))))
		writeLength8(&buf, len(s))
		buf.WriteString(s)
		buf.WriteByte(0)
		return buf.Bytes()
	}
	units := utf16.Encode([]rune(s))
	writeLength16(&buf, len(units))
	for _, u := range units {
		_ = binary.Write(&buf, binary.LittleEndian, u)
	}
	buf.Write([]byte{0, 0})
	return buf.Bytes()
}

func writeLength8(buf *bytes.Buffer, v int) {
	if v > 0x7f {
		buf.WriteByte(byte(v>>8) | 0x80)
		buf.WriteByte(byte(v))
		return
	}
	buf.WriteByte(byte(v))
}

func writeLength16(buf *bytes.Buffer, v int) {
	_ = binary.Write(buf, binary.LittleEndian, uint16(v))
}

type axmlAttr struct {
	nameIdx  uint32
	dataType byte
	data     uint32
	rawValue uint32
}

func startElement(nameIdx uint32, attrs []axmlAttr) []byte {
	body := make([]byte, 20+20*len(attrs))
	binary.LittleEndian.PutUint32(body[0:], noIndex)
	binary.LittleEndian.PutUint32(body[4:], nameIdx)
	binary.LittleEndian.PutUint16(body[8:], 20)
	binary.LittleEndian.PutUint16(body[10:], 20)
	binary.LittleEndian.PutUint16(body[12:], uint16(len(attrs)))
	for i, a := range attrs {
		off := 20 + i*20
		binary.LittleEndian.PutUint32(body[off:], noIndex)
		binary.LittleEndian.PutUint32(body[off+4:], a.nameIdx)
		binary.LittleEndian.PutUint32(body[off+8:], a.rawValue)
		binary.LittleEndian.PutUint16(body[off+12:], 8)
		body[off+15] = a.dataType
		binary.LittleEndian.PutUint32(body[off+16:], a.data)
	}
	return nodeChunk(chunkTypeStartElement, body)
}

func endElement(nameIdx uint32) []byte {
	body := make([]byte, 8)
	binary.LittleEndian.PutUint32(body[0:], noIndex)
	binary.LittleEndian.PutUint32(body[4:], nameIdx)
	return nodeChunk(chunkTypeEndElement, body)
}

func nodeChunk(chunkType uint16, body []byte) []byte {
	out := make([]byte, 16+len(body))
	binary.LittleEndian.PutUint16(out[0:], chunkType)
	binary.LittleEndian.PutUint16(out[2:], 16)
	binary.LittleEndian.PutUint32(out[8:], 0)
	binary.LittleEndian.PutUint32(out[12:], noIndex)
	copy(out[16:], body)
	return finishChunk(out)
}

func resourceMap(ids []uint32) []byte {
	chunk := make([]byte, 8+4*len(ids))
	binary.LittleEndian.PutUint16(chunk[0:], chunkTypeResourceMap)
	binary.LittleEndian.PutUint16(chunk[2:], 8)
	for i, id := range ids {
		binary.LittleEndian.PutUint32(chunk[8+i*4:], id)
	}
	return finishChunk(chunk)
}

func xmlRoot(children []byte) []byte {
	out := make([]byte, 8+len(children))
	binary.LittleEndian.PutUint16(out[0:], chunkTypeXML)
	binary.LittleEndian.PutUint16(out[2:], 8)
	copy(out[8:], children)
	return finishChunk(out)
}

// finishChunk 补齐 4 字节对齐并回填块长度字段。
func finishChunk(chunk []byte) []byte {
	if pad := (4 - len(chunk)%4) % 4; pad > 0 {
		chunk = append(chunk, make([]byte, pad)...)
	}
	binary.LittleEndian.PutUint32(chunk[4:], uint32(len(chunk)))
	return chunk
}

type manifestFixture struct {
	Package     string
	VersionName string
	VersionCode int
	MinSDK      int
	TargetSDK   int
}

// buildAXML 生成一份结构完整（manifest + uses-sdk）的二进制 AndroidManifest.xml。
func buildAXML(t *testing.T, utf8Pool, withResourceMap bool, f manifestFixture) []byte {
	t.Helper()
	pool := newAxmlStringPool()

	manifestIdx := pool.add("manifest")
	usesSdkIdx := pool.add("uses-sdk")
	codeIdx := pool.add("versionCode")
	nameAttrIdx := pool.add("versionName")
	pkgIdx := pool.add("package")
	minIdx := pool.add("minSdkVersion")
	targetIdx := pool.add("targetSdkVersion")

	versionNameIdx := pool.add(f.VersionName)
	pkgValueIdx := pool.add(f.Package)

	manifestAttrs := []axmlAttr{
		{nameIdx: pkgIdx, dataType: typeString, data: pkgValueIdx, rawValue: pkgValueIdx},
		{nameIdx: codeIdx, dataType: typeIntDec, data: uint32(f.VersionCode), rawValue: noIndex},
		{nameIdx: nameAttrIdx, dataType: typeString, data: versionNameIdx, rawValue: versionNameIdx},
	}
	sdkAttrs := []axmlAttr{
		{nameIdx: minIdx, dataType: typeIntDec, data: uint32(f.MinSDK), rawValue: noIndex},
		{nameIdx: targetIdx, dataType: typeIntDec, data: uint32(f.TargetSDK), rawValue: noIndex},
	}

	ids := make([]uint32, len(pool.values))
	if withResourceMap {
		ids[codeIdx] = attrVersionCode
		ids[nameAttrIdx] = attrVersionName
		ids[minIdx] = attrMinSDK
		ids[targetIdx] = attrTargetSDK
	}

	var children bytes.Buffer
	children.Write(pool.encode(utf8Pool))
	if withResourceMap {
		children.Write(resourceMap(ids))
	}
	children.Write(startElement(manifestIdx, manifestAttrs))
	children.Write(startElement(usesSdkIdx, sdkAttrs))
	children.Write(endElement(usesSdkIdx))
	children.Write(endElement(manifestIdx))
	return xmlRoot(children.Bytes())
}

func buildAPK(t *testing.T, manifest []byte) ([]byte, int64) {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, err := zw.Create("AndroidManifest.xml")
	require.NoError(t, err)
	_, err = w.Write(manifest)
	require.NoError(t, err)
	w, err = zw.Create("classes.dex")
	require.NoError(t, err)
	_, err = w.Write([]byte("dex-payload"))
	require.NoError(t, err)
	require.NoError(t, zw.Close())
	return buf.Bytes(), int64(buf.Len())
}

// ===================== 用例 =====================

func TestFromAPK_解析AndroidManifest元数据(t *testing.T) {
	fixture := manifestFixture{Package: "com.csergy.invapp", VersionName: "1.0.9", VersionCode: 10, MinSDK: 23, TargetSDK: 34}
	blob, size := buildAPK(t, buildAXML(t, true, true, fixture))

	meta, err := FromAPK(bytes.NewReader(blob), size)
	require.NoError(t, err)
	assert.Equal(t, "com.csergy.invapp", meta.PackageName)
	assert.Equal(t, "1.0.9", meta.VersionName)
	assert.Equal(t, int64(10), meta.VersionCode)
	assert.Equal(t, 23, meta.MinSDK)
	assert.Equal(t, 34, meta.TargetSDK)
}

func TestFromManifest_UTF16字符串池(t *testing.T) {
	fixture := manifestFixture{Package: "com.csergy.invapp", VersionName: "2.0.0", VersionCode: 20, MinSDK: 24, TargetSDK: 35}

	meta, err := FromManifest(buildAXML(t, false, true, fixture))
	require.NoError(t, err)
	assert.Equal(t, fixture.Package, meta.PackageName)
	assert.Equal(t, fixture.VersionName, meta.VersionName)
	assert.Equal(t, int64(20), meta.VersionCode)
}

func TestFromManifest_无资源映射表时按属性名回退(t *testing.T) {
	fixture := manifestFixture{Package: "com.csergy.invapp", VersionName: "1.2.0", VersionCode: 12, MinSDK: 21, TargetSDK: 33}

	meta, err := FromManifest(buildAXML(t, true, false, fixture))
	require.NoError(t, err)
	assert.Equal(t, "1.2.0", meta.VersionName)
	assert.Equal(t, int64(12), meta.VersionCode)
	assert.Equal(t, 21, meta.MinSDK)
	assert.Equal(t, 33, meta.TargetSDK)
}

func TestFromManifest_中文字符串池正确解码(t *testing.T) {
	fixture := manifestFixture{Package: "com.csergy.逆变器", VersionName: "1.0.0-测试", VersionCode: 3}

	meta, err := FromManifest(buildAXML(t, true, true, fixture))
	require.NoError(t, err)
	assert.Equal(t, "com.csergy.逆变器", meta.PackageName)
	assert.Equal(t, "1.0.0-测试", meta.VersionName)
}

func TestFromManifest_minSdk为预览版代号时忽略而非报错(t *testing.T) {
	pool := newAxmlStringPool()
	manifestIdx := pool.add("manifest")
	usesSdkIdx := pool.add("uses-sdk")
	pkgIdx := pool.add("package")
	minIdx := pool.add("minSdkVersion")
	pkgValueIdx := pool.add("com.csergy.invapp")
	previewIdx := pool.add("S")

	ids := make([]uint32, len(pool.values))
	ids[minIdx] = attrMinSDK

	var children bytes.Buffer
	children.Write(pool.encode(true))
	children.Write(resourceMap(ids))
	children.Write(startElement(manifestIdx, []axmlAttr{
		{nameIdx: pkgIdx, dataType: typeString, data: pkgValueIdx, rawValue: pkgValueIdx},
	}))
	children.Write(startElement(usesSdkIdx, []axmlAttr{
		{nameIdx: minIdx, dataType: typeString, data: previewIdx, rawValue: previewIdx},
	}))
	children.Write(endElement(usesSdkIdx))
	children.Write(endElement(manifestIdx))

	meta, err := FromManifest(xmlRoot(children.Bytes()))
	require.NoError(t, err)
	assert.Equal(t, 0, meta.MinSDK)
	assert.Equal(t, "com.csergy.invapp", meta.PackageName)
}

func TestFromAPK_非压缩包返回错误(t *testing.T) {
	_, err := FromAPK(bytes.NewReader([]byte("not-a-zip")), 9)
	assert.Error(t, err)
}

func TestFromAPK_缺少AndroidManifest返回错误(t *testing.T) {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, err := zw.Create("classes.dex")
	require.NoError(t, err)
	_, err = w.Write([]byte("dex"))
	require.NoError(t, err)
	require.NoError(t, zw.Close())

	_, err = FromAPK(bytes.NewReader(buf.Bytes()), int64(buf.Len()))
	require.Error(t, err)
	assert.Contains(t, err.Error(), "AndroidManifest.xml")
}

func TestFromManifest_非二进制XML返回错误(t *testing.T) {
	_, err := FromManifest([]byte("<manifest package=\"x\"/>"))
	assert.Error(t, err)
}

func TestFromManifest_缺少package属性返回错误(t *testing.T) {
	pool := newAxmlStringPool()
	manifestIdx := pool.add("manifest")
	var children bytes.Buffer
	children.Write(pool.encode(true))
	children.Write(startElement(manifestIdx, nil))
	children.Write(endElement(manifestIdx))

	_, err := FromManifest(xmlRoot(children.Bytes()))
	require.Error(t, err)
	assert.Contains(t, err.Error(), "package")
}
