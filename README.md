# Moon

一款面向 Windows 竖屏副显示器的实时月相壁纸。它使用 NASA Scientific Visualization Studio 的高清月相与天平动数据，并按照河南郑州的观测位置校正月面的天空朝向，让屏幕中的月亮尽量接近抬头肉眼所见。

## 特点

- NASA 4K 月面素材，保留真实地形细节
- 根据日期显示真实月相，根据郑州当前时刻校正月面旋转角度
- 1600 × 2560 纯黑竖屏构图，适合 OLED 和黑色系桌面
- 每两小时无窗口后台更新，登录后自动恢复
- 自动感知显示器接入与断开，在竖屏副屏和笔记本横屏构图间切换
- 可预下载全年每日素材，下载完成后日常运行无需联网
- 网络暂时不可用时继续使用最后一张有效壁纸

## 环境

- Windows 10 或 Windows 11
- Python 3.10 或更高版本（建议从 [python.org](https://www.python.org/downloads/windows/) 安装）
- 竖向副显示器，或一台 2560 × 1600 的笔记本电脑

## 安装

克隆仓库后，在 PowerShell 中进入项目目录并运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

安装脚本会安装 `Pillow` 和 `NumPy`，注册两个 Windows 计划任务，并立即生成第一张壁纸。首次运行需要联网；全年离线图库约占 1.6 GB，会在后台逐步补齐。

## 更新机制

- `Henan NASA Moon Wallpaper`：登录后以及每两小时运行，更新本地天空朝向；每天采用一张固定时刻的高清月面底图，避免频繁下载。
- `Henan NASA Moon Offline Library`：登录后以及每天 03:30 检查全年图库；每年 11 月起自动尝试发现下一年度 NASA 数据。
- `Moon Display Watcher`：登录后静默驻留，只监测显示器拓扑；连接或断开显示器稳定约 7 秒后立即切换构图。

三个任务均使用 `pythonw.exe` 静默执行，不会弹出命令行窗口。

## 手动运行

```powershell
python .\update_moon_from_nasa.py
python .\prefetch_nasa_moon_year.py --workers 6
```

第二条命令会下载全年素材，流量与磁盘占用约 1.6 GB。

## 卸载

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

卸载只移除计划任务，不删除已下载图片。需要释放空间时，可自行删除 `cache` 文件夹。

## 当前设计范围

此版本是为河南郑州附近、1600 × 2560 竖屏副显示器和 2560 × 1600 笔记本屏幕量身设计的。观测坐标、画布尺寸和月亮位置目前位于 `update_moon_from_nasa.py` 顶部及 `compose()` 中，可以按需要调整。

应用规则刻意避免覆盖桌面的横向主屏壁纸：只要检测到活动的竖屏，月相只应用到竖屏；没有竖屏时，才把横屏构图应用到当前唯一的笔记本屏幕。

## 数据来源

月面图像与天文数据来自 [NASA Scientific Visualization Studio](https://svs.gsfc.nasa.gov/)。仓库只包含程序代码；NASA 原始图片会在用户电脑上按需下载。

## License

[MIT](LICENSE)
