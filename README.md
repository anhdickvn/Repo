# ChatApp — ChatCraft-style Minecraft client

Bản cập nhật giao diện và tiện ích:

- Giao diện chính 3 tab dưới cùng: **ChatCraft / Logs / Settings**.
- Logs lưu toàn bộ dòng chat/log phát sinh trong **hôm nay** và tự xoá khi sang ngày mới.
- Settings có **Tối / Sáng / Tự động**.
- Server mặc định được thêm sẵn: **Tôi Chơi NetWork — proxy.toichoi.com:54321**.
- Form Add Server điền sẵn các giá trị trên; username là ô trống để người chơi tự đặt, không có username ví dụ.
- Khi mở một server, app tự kết nối. Nếu có mật khẩu đã lưu: **/login → chờ 2 giây → hotbar 5 (Compass) → chuột phải → chờ GUI → click Diamond Axe ở ô 23**. Nếu user tự nhập `/login`, flow 2 giây tương tự cũng chạy.
- Cặp sách gồm **Túi đồ / GUI / Vị trí**. GUI server được nhận và lưu khi server gửi packet, nhưng **không tự bật sheet** khi `/ah`, `/pv` hoặc lệnh khác mở GUI; người dùng phải bấm Cặp sách → GUI.
- Vị trí hiển thị **X/Y/Z + map/dimension**, có nút di chuyển và Jump. WASD từ bàn phím vật lý được gửi bằng packet Player Position đúng protocol 340; không còn gửi payload Player Position vào packet Player Position And Look.
- Tab completion người chơi vẫn hoạt động: `/w WhatDid` → Tab → tên khớp từ Player List/Tab Complete.
- Resource Pack: khi server gửi pack, app tự **ACCEPTED → tải ZIP → giải nén → SUCCESSFULLY_LOADED** trước khi chạy flow menu; PNG thật của server được ưu tiên. Nếu server pack chỉ override một phần, app tự tải **asset vanilla Minecraft 1.12.2 chính thức** vào sandbox làm fallback để hiển thị icon item thật, không dùng emoji.
- Tooltip giữ tên màu, Lore, click trái/phải và nút `...`.
- Kết nối TCP vẫn có reconnect khi POSIX error 53; không disconnect chỉ vì app view biến mất. iOS vẫn có thể terminate process khi force-quit.

## Build

Project dùng SwiftUI + ZIPFoundation và có thể build bằng Xcode/XcodeGen hoặc workflow GitHub Actions có sẵn trong `.github/workflows/build-ipa.yml`.

## Giới hạn protocol

Client hiện tập trung vào protocol Minecraft Java **1.12–1.12.2 (338–340)**. Resource pack model parsing được thiết kế cho cấu trúc resource pack của các phiên bản này; custom item quá đặc thù có thể cần thêm predicate/NBT renderer riêng.
