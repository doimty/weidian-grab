export ARCHS = arm64 arm64e

THEOS_PACKAGE_SCHEME = roothide

export DEBUG = 0
export FINALPACKAGE = 1

TARGET := iphone:clang:16.5:15.0

INSTALL_TARGET_PROCESSES = WDBuyerUniv

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeidianGrab
WeidianGrab_FILES = Tweak.x WDGCore.m WDGPanel.m WDGTradeObserver.m WDGOrderService.m WDGCart.m
WeidianGrab_CFLAGS = -fobjc-arc
WeidianGrab_FRAMEWORKS = Foundation UIKit
WeidianGrab_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
