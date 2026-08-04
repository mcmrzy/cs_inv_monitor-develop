# 联通一键登录 SDK（com.unicom.online.account，随 JVerify 引入）
# 以可选依赖方式引用 BouncyCastle（SM2/SM3 国密算法），运行时不打包该类库、
# 设备缺失时 SDK 内部走降级路径。AGP 8.12+ 的 R8 将 missing class 升级为
# 构建错误（8.11 及之前为警告），需显式 dontwarn 抑制。
-dontwarn org.bouncycastle.**
