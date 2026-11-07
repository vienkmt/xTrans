#!/usr/bin/env bash
#
# Build bản Release của xTrans và đóng gói thành DMG cài đặt.
#
# Cách dùng:
#   scripts/build-dmg.sh                 # build + đóng gói → dist/xTrans-<phiên bản>.dmg
#   scripts/build-dmg.sh --no-layout     # bỏ bước dùng Finder sắp xếp cửa sổ DMG (vd chạy trên CI)
#   scripts/build-dmg.sh --notarize <keychain-profile>
#                                        # thêm bước gửi Apple notarize + staple
#                                        # (cần chứng chỉ "Developer ID Application" – xem ghi chú cuối file)
#
# Phiên bản lấy từ MARKETING_VERSION trong Xcode (target xTrans → General → Version).
#
set -euo pipefail

# ---------- Cấu hình ----------
APP_NAME="xTrans"
SCHEME="xTrans"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/xTrans.xcodeproj"
BACKGROUND="$ROOT/scripts/dmg/background.tiff"
DIST="$ROOT/dist"

LAYOUT=1
NOTARY_PROFILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-layout) LAYOUT=0; shift ;;
    --notarize)  NOTARY_PROFILE="${2:?Thiếu tên keychain profile sau --notarize}"; shift 2 ;;
    -h|--help)   sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Tham số không hợp lệ: $1" >&2; exit 1 ;;
  esac
done

step() { printf '\n\033[1;34m▸ %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# Thư mục tạm, tự dọn khi kết thúc (kể cả khi lỗi)
WORK="$(mktemp -d "${TMPDIR:-/tmp}/xtrans-dmg.XXXXXX")"
MOUNT_DIR=""
cleanup() {
  if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || hdiutil detach "$MOUNT_DIR" -force -quiet 2>/dev/null || true
  fi
  [[ -n "$WORK" && -d "$WORK" && "$WORK" == *xtrans-dmg.* ]] && rm -rf "$WORK"
}
trap cleanup EXIT

[[ -f "$BACKGROUND" ]] || fail "Không thấy ảnh nền DMG: $BACKGROUND"
SETFILE="$(xcrun -f SetFile 2>/dev/null || true)"

# ---------- 1. Phiên bản ----------
VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')"
BUILD_NUMBER="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}')"
[[ -n "$VERSION" ]] || fail "Không đọc được MARKETING_VERSION"
DMG_PATH="$DIST/$APP_NAME-$VERSION.dmg"
echo "Phiên bản: $VERSION (build $BUILD_NUMBER)"

# ---------- 2. Archive bản Release ----------
step "Build Release (archive)…"
ARCHIVE="$WORK/$APP_NAME.xcarchive"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" -derivedDataPath "$WORK/DerivedData" \
  archive -quiet || fail "Archive thất bại"
APP="$ARCHIVE/Products/Applications/$APP_NAME.app"
[[ -d "$APP" ]] || fail "Không thấy $APP_NAME.app trong archive"

# ---------- 3. Kiểm tra chữ ký ----------
step "Kiểm tra chữ ký…"
codesign --verify --deep --strict "$APP" || fail "Chữ ký app không hợp lệ"
SIGN_INFO="$(codesign -dvv "$APP" 2>&1 || true)"   # lưu vào biến, tránh grep -q + pipefail báo sai
printf '%s\n' "$SIGN_INFO" | grep -E "^(Authority|TeamIdentifier)=" | head -2 || true
if [[ "$SIGN_INFO" == *"(runtime)"* ]]; then
  echo "Hardened Runtime: bật"
else
  echo "⚠︎ Chưa bật Hardened Runtime — sẽ không notarize được"
fi

# ---------- 4. Chuẩn bị nội dung DMG ----------
step "Chuẩn bị nội dung DMG…"
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
cp "$BACKGROUND" "$STAGE/.background/background.tiff"

RW_DMG="$WORK/rw.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -size 200m "$RW_DMG" -quiet

# ---------- 5. Icon ổ đĩa + bố cục cửa sổ ----------
if mount | grep -q " on /Volumes/$APP_NAME "; then
  fail "Đang có ổ /Volumes/$APP_NAME được mở — hãy tháo (Eject) rồi chạy lại"
fi
step "Gắn DMG tạm để chỉnh giao diện…"
MOUNT_DIR="/Volumes/$APP_NAME"
hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -quiet

if [[ "$LAYOUT" == 1 ]]; then
  step "Sắp xếp cửa sổ DMG bằng Finder (lần đầu macOS có thể hỏi quyền Automation)…"
  if ! osascript <<EOF
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of container window to {150, 190}
    set position of item "Applications" of container window to {490, 190}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
  then
    echo "⚠︎ Không sắp xếp được cửa sổ (thiếu quyền Automation?) — DMG vẫn dùng được, chỉ không có nền/vị trí icon"
  fi
fi

# Icon riêng cho ổ đĩa (dùng icon app) — làm SAU bước Finder, vì Finder có thể ghi đè/xoá file này
cp "$STAGE/$APP_NAME.app/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
if [[ -n "$SETFILE" ]]; then
  "$SETFILE" -a C "$MOUNT_DIR"
  "$SETFILE" -a V "$MOUNT_DIR/.VolumeIcon.icns"
else
  echo "⚠︎ Không có SetFile (Xcode) — ổ DMG sẽ dùng icon mặc định"
fi
[[ -f "$MOUNT_DIR/.VolumeIcon.icns" ]] || echo "⚠︎ Không ghi được icon ổ đĩa"

sync
hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet
MOUNT_DIR=""

# ---------- 6. Nén thành DMG cuối ----------
step "Nén DMG…"
mkdir -p "$DIST"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH" -quiet
hdiutil verify "$DMG_PATH" -quiet || fail "DMG lỗi checksum"

# ---------- 7. (Tuỳ chọn) Notarize ----------
if [[ -n "$NOTARY_PROFILE" ]]; then
  [[ "$SIGN_INFO" == *"Authority=Developer ID Application"* ]] \
    || fail "Notarize cần app ký bằng 'Developer ID Application' (hiện đang là chứng chỉ khác)"
  step "Gửi Apple notarize (có thể mất vài phút)…"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

# ---------- Xong ----------
step "Hoàn tất"
ls -lh "$DMG_PATH" | awk '{print "File: " $NF "  (" $5 ")"}'
echo "SHA-256: $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Lưu ý: DMG chưa notarize — máy khác cần chuột phải → Open (hoặc Privacy & Security → Open Anyway)."
fi

# ---------------------------------------------------------------------------
# Ghi chú notarize (khi đã có Apple Developer Program):
#   1. Xcode → target xTrans → Signing & Capabilities: Team = tài khoản trả phí,
#      Signing Certificate (Release) = "Developer ID Application".
#   2. Lưu thông tin đăng nhập notarytool một lần:
#        xcrun notarytool store-credentials xtrans-notary \
#          --apple-id <email> --team-id <TEAM_ID> --password <app-specific-password>
#   3. Chạy: scripts/build-dmg.sh --notarize xtrans-notary
# ---------------------------------------------------------------------------
