SHELL := /bin/sh

.PHONY: dmg app clean-dist

# Release .app plus a classic drag-to-Applications DMG.
# Requires a Mac with Xcode. Usage: make dmg
# Optional: make dmg VERSION=0.1.0
dmg:
	./Scripts/create-dmg.sh

app:
	./Scripts/create-dmg.sh --app-only

clean-dist:
	rm -rf dist build/DerivedData
