TARGET := iphone:clang:latest:15.0

# roothide 的 scheme 在 roothide/theos 这个 fork 的 vendor/mod/roothide 下，
# 上游 theos/theos 没有。CI 里 clone 的就是 roothide/theos。
THEOS_PACKAGE_SCHEME = roothide
ARCHS = arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeidianGrab

WeidianGrab_FILES = Tweak.x
WeidianGrab_CFLAGS = -fobjc-arc
WeidianGrab_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk