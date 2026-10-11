# Batterie — Akku-Monitor für iPod touch 4 (iOS 6.1, ARMv7), Theos.
TARGET = iphone:clang:7.1:6.0
ARCHS  = armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Batterie

Batterie_FILES  = $(wildcard src/*.m)
Batterie_FRAMEWORKS = UIKit CoreGraphics Foundation QuartzCore
Batterie_CFLAGS  = -fobjc-arc -O2 -Wall

include $(THEOS_MAKE_PATH)/application.mk
