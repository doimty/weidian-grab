TARGET := iphone:clang:latest:15.0
ARCHS = arm64e

# roothide 用 libhooker，不是 CydiaSubstrate。
# rootless 方案让 Theos 链接 /usr/lib/libsubstrate.dylib 而不是
# /Library/Frameworks/CydiaSubstrate.framework —— 后者在这台设备上不存在，
# 会导致 dlopen 失败、libhooker 静默跳过（0.1.0 就是这么废的）。
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeidianGrab

WeidianGrab_FILES = Tweak.x
WeidianGrab_CFLAGS = -fobjc-arc
WeidianGrab_FRAMEWORKS = Foundation UIKit
WeidianGrab_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk