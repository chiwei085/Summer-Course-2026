PACKAGE_PATH ?= packages
MAIN ?= example/main.typ
BASE := $(basename $(MAIN))
PDF ?= $(BASE).pdf
PPTX ?= $(BASE).pptx
PNG_DIR ?= $(BASE)-png
PNG_PPI ?= 216
PNG_PATTERN := $(PNG_DIR)/page-{0p}.png
CHEATSHEET ?= $(BASE)-cheatsheet.png
CHEATSHEET_TILE ?= 640x360
CHEATSHEET_COLUMNS ?= 3
CHEATSHEET_GEOMETRY ?= +16+16
LOCAL_PACKAGE_DIR := $(HOME)/.local/share/typst/packages/local/summer-course
LOCAL_PACKAGE_VERSION := 0.1.0
LOCAL_PACKAGE_SOURCE := $(abspath packages/local/summer-course/$(LOCAL_PACKAGE_VERSION))

.PHONY: build pdf pptx png cheatsheet watch clean install-local-package

build: pdf

pdf:
	typst compile --package-path $(PACKAGE_PATH) $(MAIN) $(PDF)

pptx:
	TYPST_PACKAGE_PATH=$(abspath $(PACKAGE_PATH)) touying compile --root . --format pptx --output $(PPTX) $(MAIN)

png:
	mkdir -p $(PNG_DIR)
	typst compile --package-path $(PACKAGE_PATH) --ppi $(PNG_PPI) $(MAIN) $(PNG_PATTERN)

cheatsheet: png
	magick montage $(PNG_DIR)/*.png -thumbnail $(CHEATSHEET_TILE) -tile $(CHEATSHEET_COLUMNS)x -geometry $(CHEATSHEET_GEOMETRY) -background white $(CHEATSHEET)

watch:
	typst watch --package-path $(PACKAGE_PATH) $(MAIN) $(PDF)

clean:
	rm -f $(PDF) $(PPTX) $(CHEATSHEET)
	rm -rf $(PNG_DIR)

install-local-package:
	mkdir -p $(LOCAL_PACKAGE_DIR)
	ln -sfn $(LOCAL_PACKAGE_SOURCE) $(LOCAL_PACKAGE_DIR)/$(LOCAL_PACKAGE_VERSION)
