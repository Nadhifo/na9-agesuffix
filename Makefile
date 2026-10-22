TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NA9AgeSuffix
NA9AgeSuffix_FILES = Tweak.m
NA9AgeSuffix_CFLAGS = -fobjc-arc
NA9AgeSuffix_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
