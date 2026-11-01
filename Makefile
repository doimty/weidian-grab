TARGET := iphone:clang:latest:15.0

# roothide 打包方案：Theos 会自己把 ARCHS 设成 arm64e、
# 把 load command 指向 libsubstrate（libhooker）而不是 CydiaSubstrate 框架、
# 并把 control 的 Architecture 写成 iphoneos-arm64e。
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeidianGrab

WeidianGrab_FILES = Tweak.x
WeidianGrab_CFLAGS = -fobjc-arc
WeidianGrab_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
