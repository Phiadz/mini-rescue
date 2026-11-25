# Hướng dẫn agent: Floodline

Tài liệu này tóm tắt cấu trúc và luồng chạy đang có trong source hiện tại. Các
tài liệu có trước như `README`, `CONTRIBUTING.md` và roadmap mô tả bản MVP, chỉ
dùng để tham khảo lịch sử/ý tưởng; không coi chúng là đặc tả hay hướng dẫn chuẩn
cho phiên bản hiện tại. Khi thông tin khác nhau, ưu tiên kiểm chứng source và
test hiện tại.

## Tổng quan

Floodline là game 2D quản lý mạng đường và cứu hộ trong mùa lũ. Người chơi nối
đường trên lưới, theo dõi nước dâng/rút, điều phối xe tải và ca-nô, đặt tuyến phà
vượt sông, và xử lý SOS trong các đợt chơi.

- Engine: `project.godot` khai báo feature Godot 4.7; xác nhận phiên bản runtime
  đang dùng từ môi trường dự án, không lấy phiên bản trong tài liệu MVP làm chuẩn.
- Renderer: Compatibility (`GL Compatibility` trong `project.godot`).
- Khung hình logic: 1280 x 720.
- Lưới bản đồ: 32 cột x 18 hàng, mỗi ô 40 px.
- Scene khởi động: `ui/boot.tscn`; scene chơi: `game/main.tscn`.
- Ngôn ngữ code: GDScript; tên file/hàm/biến `snake_case`, class `PascalCase`,
  hằng số `UPPER_SNAKE`, thụt dòng bằng tab.

## Bắt đầu đọc code

1. `project.godot`: autoload, scene khởi động, renderer và kích thước khung hình.
2. `autoload/types.gd`, `autoload/config.gd`, `autoload/event_bus.gd`: enum,
   tham số game và hợp đồng tín hiệu.
3. `autoload/game_manager.gd`: vòng đời game, wave, tạm dừng, cửa hàng, camera.
4. `graph/graph_manager.gd`: dữ liệu đồ thị, bản đồ, tìm đường và tuyến phà.
5. `flood/flood_manager.gd`: mô phỏng nước và cập nhật trạng thái đường.
6. `rescue/rescue_manager.gd`: SOS, kho, xe, điều phối và giao hàng.
7. `ui/ui_root.gd`: ghép các màn hình và lắng nghe EventBus.
8. `data/map_saigon.json`: dữ liệu bản đồ đang được Config sử dụng.

## Luồng khởi động và vòng đời

- `project.godot` mở `ui/boot.tscn`. `ui/boot.gd` làm ấm shader, nạp trước
  scene game rồi chuyển sang `game/main.tscn`.
- `game/main.tscn` tạo World với các layer nền, lũ, đường, nút giao, nút bản đồ,
  xe và UI.
- Menu và các màn hình được quản lý bởi `ui/ui_root.gd`.
- Khi bắt đầu, `GameManager` nạp bản đồ, tạo camera/stage và FerryLayer, phát
  `game_started`, sau đó bắt đầu `wave_started(0)`.
- Các module reset/bắt đầu bằng cách lắng nghe EventBus; tránh gọi trực tiếp node
  của module khác.
- Trạng thái chính: `MENU -> PLAYING <-> WAVE_BREAK -> WON/LOST`; `PAUSED` tạm
  dừng một trạng thái đang chơi/nghỉ. Wave index bắt đầu từ 0.
- Mỗi ván có 3 wave, có khoảng nghỉ giữa wave. Quay lại menu/restart được điều
  khiển bởi `GameManager`.

## Các module và ranh giới

### Autoload (`autoload/`)

- `Types`: enum dùng chung; script autoload không khai báo `class_name`.
- `Config`: tham số cân bằng, lưới, tốc độ, nước, wave, SOS, cửa hàng.
- `EventBus`: chỉ khai báo tín hiệu; module sở hữu tín hiệu mới được emit.
- `GameManager`: điều phối vòng đời game và trạng thái.
- `AudioManager`: nhạc và âm thanh.

### Graph (`graph/`)

- `GraphManager` đọc JSON, quản lý điểm/kho, nút đường, cạnh, cổng ra vào,
  ngân sách đường và tìm đường ngắn nhất.
- Nút/cạnh đường bộ và đồ thị nước cho ca-nô được quản lý riêng trong
  `GraphManager`; dữ liệu điểm và độ cao nằm trong JSON.
- `find_path(...)` trả `PathResult`; xe được giới hạn theo `Edge.speed_factor`.
- `edge_layer.gd`, `node_layer.gd`, `junction_layer.gd` và `edge_drawer.gd`
  phụ trách hiển thị/tương tác với đồ thị.
- Feature phương tiện vượt sông hiện thực tế là tuyến phà/phao đặt thủ công:
  `place_ferry` tạo các cạnh phà đi theo các nút nước, xe tải đi được, ca-nô
  không đi cạnh phà. Tuyến có thể auto-fallback khi bến bị ngập/xóa; `ferry_layer`
  vẽ bến và tàu. Không nhầm với hệ thống phao trung chuyển hàng hóa tổng quát
  nếu chưa có code tương ứng.

### Flood (`flood/`)

- `FloodManager` mô phỏng nước trên lưới: sông/biển là nguồn, nước tràn theo 4
  hướng dựa trên địa hình và có cơ chế thoát/thấm.
- `DRY`, `SHALLOW`, `DEEP` được tính từ độ sâu; trạng thái cạnh cập nhật
  `GraphManager`, cảnh báo đi qua `EventBus`.
- Sông có ground và deck riêng: đường trên sông được xử lý như mặt cầu.
- Ô đất ngập sâu có thể được thêm vào đồ thị nước để ca-nô chạy tới.
- `flood_overlay.gd` và shader trong `flood/` hiển thị nước.

### Rescue (`rescue/`)

- `RescueManager` quản lý yêu cầu SOS, kho/hàng tồn, xe cứu hộ và xe dân.
- Xe tải/ca-nô tìm đường, lấy hàng, giao hàng, quay về; xe dân tại mỗi nhà có
  thể tự đi lấy hàng nếu tìm được đường và chưa bị loại bỏ bởi ngập.
- Điều phối có tính chi phí kẹt xe để chọn đường; kẹt xe và ưu tiên nút giao
  được xử lý bằng logic/khoảng cách, không dùng physics body.
- Signal quan trọng gồm SOS, trạng thái xe, tồn kho và kết quả cứu hộ.
- `vehicle_layer.gd` hiển thị xe; phần xe và các state của xe nằm trong
  `rescue/rescue_manager.gd`.

### Game và UI

- `game/score_system.gd`: điểm, quỹ cứu trợ, số SOS thành công/thất bại.
- `game/stage_view.gd`: camera và vùng chơi mở dần theo stage khai báo trong
  bản đồ.
- `ui/`: menu, HUD, pause, hướng dẫn, cửa hàng, kết quả, SOS/cảnh báo, audio.
  UI lắng nghe EventBus và gọi API công khai, không truy cập trực tiếp scene
  nội bộ của module khác.

## Dữ liệu và tài nguyên

- `data/map_saigon.json`: bản đồ chính (`Config.MAP_PATH`), gồm nodes, stages,
  terrain và các mảng lưới elevation/water/spill/boat/bank/link nếu có.
- `data/map_01.json`: một file bản đồ khác; kiểm tra schema trước khi dùng.
- `assets/icons/`, `assets/images/`, `assets/fonts/`, `assets/sfx/`: tài nguyên
  hình, ảnh, font và âm thanh.
- `assets/scenes/`: scene tài nguyên cho các điểm bản đồ.
- `tools/`: scene/script hỗ trợ tạo dữ liệu lưới/địa hình.
- `.godot/` là cache của Godot, không phải source cần chỉnh sửa.

## Thêm feature an toàn

- Trước khi sửa, đọc module chính và các enum/tín hiệu/config liên quan; tìm các
  call site và test đang có.
- Giao tiếp giữa module bằng API/autoload và EventBus. Không phụ thuộc vào
  đường dẫn node tương đối sang scene của module khác.
- Khai báo tham số cân bằng trong `autoload/config.gd` thay vì rải magic number.
- Giữ nguyên ý nghĩa enum và API công khai; nếu cần đổi hợp đồng/tín hiệu, cập
  nhật cả bên phát, bên nghe, UI và test.
- EventBus chỉ khai báo tín hiệu; chỉ module chủ sở hữu mới phát tín hiệu đó.
- Không sửa `game/main.tscn` nếu feature chỉ cần thêm logic vào layer/module đã
  có. Thay đổi scene có thể gây conflict; kiểm tra các scene test trước.
- Khi thêm feature, thêm test tập trung trong `tests/`; ưu tiên scene/test
  `*_auto` đã có cho Graph, Flood, Rescue, Game và Feature D.

## Test

Thư mục `tests/` có scene test thủ công và test tự động. Tên `*_auto.tscn` là
các entry point phù hợp để chạy headless. Ví dụ, từ thư mục project:

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/test_game_auto.tscn
```

Chọn test gần với module vừa sửa trước; nếu sửa hợp đồng liên module, chạy thêm
test integration/Game. Test script thường thoát mã 0 khi đạt và 1 nếu thất bại.

## Tài liệu MVP có trước

`README`, `CONTRIBUTING.md`, `FEATURE_XE_DAN_VA_NANG_CAP_XE_CUU_HO.md` và
`TIEN_DO_VA_DINH_HUONG_NANG_CAP.md` được viết cho MVP hoặc các giai đoạn cũ.
Chúng có thể hữu ích để hiểu lịch sử, ý tưởng ban đầu và quy trình nhóm, nhưng
không phải nguồn chuẩn về feature, kiến trúc, cấu trúc file, phiên bản engine
hay quy ước hiện tại. Hãy xác nhận mọi chi tiết cần thiết trong source/config
và test hiện hành. `project.godot` hiện vẫn đặt `config/name` là
`"New Game Project"`; tên này không mô tả đầy đủ trò chơi.

## Kế hoạch Endless và giao việc agent

- Khi làm các feature Endless, card draft, flood/boat, hạ tầng, camera hoặc
  gameplay UI, hãy đọc
  [`docs/endless_gameplay_and_ui_plan.md`](docs/endless_gameplay_and_ui_plan.md)
  để biết mục tiêu và các quyết định thiết kế.
- Đọc thêm
  [`docs/endless_gameplay_team_assignments.md`](docs/endless_gameplay_team_assignments.md)
  để biết owner đề xuất, ranh giới file/API, thứ tự bàn giao và tiêu chí kiểm tra.
- Kế hoạch Endless mô tả hành vi mong muốn; source/config/test mô tả hành vi
  đã triển khai. Bản giao việc là đề xuất phân công, không chứng minh một task
  đã được giao, bắt đầu hoặc hoàn tất. Xác nhận với Lead trước khi nhận task,
  merge hoặc thay đổi quyết định còn mở.
- `FEATURE_XE_DAN_VA_NANG_CAP_XE_CUU_HO.md` chỉ là tài liệu giai đoạn cũ và
  tham khảo cách phân rã task. Không mang cơ chế Shop, giá tiền, branch hay
  trạng thái hoàn thành cũ sang kế hoạch Endless nếu chưa được xác nhận riêng.
- `AGENTS.md` giúp agent đọc được đường dẫn tài liệu khi agent/tool nạp hướng
  dẫn repository; nó không tự đảm bảo mọi AI bên ngoài đều nhận nội dung này
  trong context. Khi khởi chạy AI/subagent khác, hãy yêu cầu đọc hai tài liệu
  trên và nêu rõ task/owner/API liên quan trong prompt.
- Với agent chạy ở branch/clone khác, các file tài liệu phải có mặt trong
  branch/clone đó (được commit/chia sẻ hoặc đính kèm); đường dẫn trong
  `AGENTS.md` không tự đồng bộ file qua các workspace.
