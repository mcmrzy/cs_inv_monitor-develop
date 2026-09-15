// Command esa-purge 手动查询 ESA 站点或强制刷新下载页元数据缓存。
//
// 用法：
//
//	esa-purge -list-sites
//	esa-purge -site-id <ID> [-host download.jiuxiaoyw.online]
//
// 凭据从环境变量读取：ALIYUN_ACCESS_KEY_ID、ALIYUN_ACCESS_KEY_SECRET。
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"inv-api-server/internal/service"
)

func main() {
	listSites := flag.Bool("list-sites", false, "列出账号下 ESA 站点")
	siteID := flag.String("site-id", os.Getenv("ESA_SITE_ID"), "ESA Site ID")
	host := flag.String("host", "download.jiuxiaoyw.online", "刷新目标主机")
	flag.Parse()

	ak := os.Getenv("ALIYUN_ACCESS_KEY_ID")
	sk := os.Getenv("ALIYUN_ACCESS_KEY_SECRET")
	if ak == "" || sk == "" {
		fmt.Fprintln(os.Stderr, "需要环境变量 ALIYUN_ACCESS_KEY_ID 与 ALIYUN_ACCESS_KEY_SECRET")
		os.Exit(2)
	}

	if *listSites {
		p := service.NewESACachePurger(ak, sk, "placeholder", *host)
		result, err := p.ListSites()
		if err != nil {
			fmt.Fprintf(os.Stderr, "ListSitesESA 失败: %v\n", err)
			os.Exit(1)
		}
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		_ = enc.Encode(result)
		return
	}

	if *siteID == "" {
		fmt.Fprintln(os.Stderr, "需要 -site-id 或环境变量 ESA_SITE_ID")
		os.Exit(2)
	}

	purger := service.NewESACachePurger(ak, sk, *siteID, *host)
	fmt.Printf("刷新 %v\n", purger.RefreshPaths())
	if err := purger.Refresh(); err != nil {
		fmt.Fprintf(os.Stderr, "刷新失败: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("已提交 ESA 刷新任务")
}
