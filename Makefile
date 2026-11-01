TARGET := iphone:clang:latest:15.0

# Theos master 只有 rootless 方案（没有 roothide 这个名字）。
# roothide 的做法是：按 rootless 编译，安装时由它的 dpkg 钩子生成
# *.roothidepatch 做路径重定位，control 里的 Architecture 改成 iphoneos-arm64e。
# 关键是 dylib 里不能链 CydiaSubstrate 框架 —— roothide 只有 libhooker，
# 所以 Tweak.x 完全不用 substrate，靠 method_setImplementation 手写 swizzle。
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeidianGrab

WeidianGrab_FILES = Tweak.x
WeidianGrab_CFLAGS = -fobjc-arc
WeidianGrab_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk