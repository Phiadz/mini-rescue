# Quy tắc làm việc chung (CONTRIBUTING)

Tài liệu này dành cho cả nhóm. Luật chơi và hợp đồng giữa các module nằm ở **Tài liệu chốt** (xem link trong nhóm chat). File này chỉ nói cách làm việc trong repo.

## 1. Chuẩn bị

- Dùng **cùng một bản Godot** với bản ghi trong `README.md` (ví dụ 4.3.x). Khác bản có thể làm file project bị đổi lung tung.
- Renderer của project là **Compatibility**. Không đổi.
- Viết code trong trình soạn thảo của Godot. Git dùng **GitHub Desktop** hoặc lệnh `git`.
- Thụt dòng bằng **Tab**, không trộn với dấu cách. Lỗi "Mixed tabs and spaces": Edit → Convert Indent to Tabs.

## 2. Ai giữ module nào

| Người | Module | Thư mục chính |
|---|---|---|
| A | Nhóm trưởng, nền tảng, dữ liệu Graph và Pathfinding | `graph/graph_manager.gd`, `map_node.gd`, `edge.gd`, `path_result.gd`; `autoload/` (types, event_bus, config); `data/`; `game/main.tscn` |
| B | Flood Engine | `flood/` |
| C | Rescue và Logistics | `rescue/` |
| D | UI/UX và Audio | `ui/`, `assets/sfx/`, `assets/fonts/` |
| E | Game Manager, Graph View (hiển thị và kéo thả đồ thị), kiến trúc, phát hành | `game/` (trừ `main.tscn`), `autoload/game_manager.gd`, `graph/node_layer.gd`, `edge_layer.gd`, `edge_view.gd`, `edge_drawer.gd` |

Mỗi người **chỉ sửa file trong module của mình**. Cần sửa file của người khác thì nhắn người đó (hoặc tạo Pull Request cho họ duyệt).

## 3. Quy tắc code

1. Tên file và biến dùng `snake_case`. Tên class dùng `PascalCase` (với `class_name`). Hằng số dùng `UPPER_SNAKE`.
2. Tên tín hiệu ở thì quá khứ: `edge_added`, `sos_failed`.
3. Khai báo kiểu rõ ràng: `func find_path(a: int, b: int) -> PathResult`.
4. **Script autoload không đặt `class_name`.**
5. Không dùng đường dẫn node tới scene của người khác (kiểu `get_node("../../Hud")`). Giao tiếp qua autoload và `EventBus`.
6. Hỏi thì gọi hàm công khai, báo tin thì phát tín hiệu qua `EventBus`. **Chỉ module chủ sở hữu mới được phát tín hiệu của mình** (bảng mục 2.4 Tài liệu chốt).
7. Không viết số cứng trong code. Tham số cân bằng nằm ở `autoload/config.gd`. Cần đổi thì báo A.
8. Chỉ số đợt (wave index) **tính từ 0**. Màn hình hiển thị là chỉ số cộng 1.
9. Không sửa chữ ký hàm công khai trong hợp đồng nếu chưa được nhóm đồng ý (xem mục 6).

## 4. Quy trình Git hằng ngày

Mỗi người làm trên **nhánh riêng**, không đẩy thẳng lên `main`.

**Lần đầu**
1. Clone repo về máy (GitHub Desktop: File → Clone repository).
2. Tạo nhánh của mình: Branch → New branch, đặt tên `feat/<module>`, ví dụ `feat/graph`, `feat/flood`, `feat/rescue`, `feat/ui`, `feat/game`.

**Mỗi ngày**
1. Trước khi làm: lấy bản mới nhất của `main` về nhánh của mình (GitHub Desktop: Branch → Update from main).
2. Làm việc, **commit nhỏ và thường xuyên**.
3. Cuối ngày: **Push** nhánh lên GitHub.

**Thông điệp commit** có tiền tố module, viết ngắn:

```
graph: thêm kiểm tra cạnh trùng
flood: sửa ngưỡng ngập sâu
ui: thêm màn hình tạm dừng
nền: thêm file khung cho B, C, D, E
```

## 5. Hợp nhánh vào `main`

- **Hợp nhánh vào thứ Hai và thứ Năm hằng tuần**, mỗi người ít nhất một lần mỗi tuần.
- Cách làm: trên GitHub, tạo **Pull Request** từ nhánh của mình vào `main`, nhờ **A** duyệt.
- Trước khi tạo Pull Request, **tự chạy thử một ván** (hoặc scene thử của mình) để chắc chắn không lỗi đỏ.
- `main` **luôn phải chạy được**. Nếu ai làm hỏng `main` thì sửa ngay trong ngày.

## 6. Muốn đổi luật chơi hoặc hợp đồng

1. Nói trong nhóm chat hoặc buổi họp.
2. Người đề xuất sửa **Tài liệu chốt** và ghi vào bảng **Nhật ký thay đổi** (mục 4.5).
3. Người bị ảnh hưởng xác nhận.
4. Sau đó mới sửa code.

## 7. Scene (`.tscn`) và xung đột

- File `.tscn` rất dễ xung đột khi hai người cùng sửa. **Không ai sửa scene của người khác.**
- `game/main.tscn` đã có sẵn chỗ cắm cho từng người. Mỗi người chỉnh script của node mình phụ trách, **không sửa `main.tscn`**. Cần thêm node thì nhắn A.
- Mỗi người có scene thử riêng trong `tests/` (ví dụ `test_graph.tscn`, `test_flood.tscn`, `test_rescue.tscn`, `test_ui.tscn`, `test_game.tscn`).
- Dữ liệu giả để thử (`mock_feed`) **chỉ dùng trong `tests/`**, không đặt vào `main.tscn`.

## 8. Những thứ không được đưa lên Git

Đã chặn trong `.gitignore`: `.godot/`, `build/`, `*.exe`, `*.tmp`. Bản build web (thư mục `build/`) không commit, sẽ nén riêng khi đăng lên itch.io.

## 9. Mốc thời gian

| Mốc | Ngày | Nội dung |
|---|---|---|
| N1 | tối 18/10 | Khung dự án đã đẩy lên GitHub, cả nhóm clone chạy được |
| M1 | 20/10 | Đóng băng luật chơi và hợp đồng module |
| M2 | 27/10 | Mỗi module chạy riêng trong scene thử |
| M3 | 03/11 | Ghép lần đầu: xe chạy, lũ làm đổi trạng thái đường |
| M4 | 10/11 | Chơi được từ đầu đến cuối; báo cáo đủ chương |
| M5 | 15/11 | **Nộp thuyết minh** |
| M6 | 20/11 | Đăng bản thử lên itch.io |
| M7 | 28/11 | Đóng băng tính năng, chỉ sửa lỗi |
| M8 | 01/12 | **Nộp game hoàn chỉnh** |

## 10. Khi bị vướng

Bị chặn quá một buổi thì **báo ngay trong nhóm chat**, đừng đợi đến buổi họp. Kèm theo thông báo lỗi nguyên văn (hoặc ảnh chụp) và mô tả bạn đã làm gì trước khi lỗi xuất hiện.
