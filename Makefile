TARGET := iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = AflatoonMenu

AflatoonMenu_FILES = Main.m Hook.m UI.m Audio.c DSP.c DNS.c
AflatoonMenu_CFLAGS = -Wno-deprecated-declarations
AflatoonMenu_OBJCFLAGS = -fobjc-arc
AflatoonMenu_FRAMEWORKS = UIKit Foundation AudioToolbox QuartzCore CoreGraphics

include $(THEOS_MAKE_PATH)/library.mk
