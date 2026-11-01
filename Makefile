TARGET := iphone:clang:latest:15.0
ARCHS = arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeidianGrab

WeidianGrab_FILES = Tweak.x
WeidianGrab_CFLAGS = -fobjc-arc
WeidianGrab_FRAMEWORKS = Foundation UIKit
WeidianGrab_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 WDBuyerUniv || true"
