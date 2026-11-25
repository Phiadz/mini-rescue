# Giao việc nhóm: Endless Gameplay, hạ tầng và UI

**Trạng thái:** Phân công và baseline cho prototype đã được người dùng chấp thuận; nhóm có thể triển khai và điều chỉnh sau playtest.
**Phạm vi thiết kế:** [`endless_gameplay_and_ui_plan.md`](./endless_gameplay_and_ui_plan.md).
**Tài liệu tham khảo cách chia việc:** [`FEATURE_XE_DAN_VA_NANG_CAP_XE_CUU_HO.md`](../FEATURE_XE_DAN_VA_NANG_CAP_XE_CUU_HO.md).

## 1. Cách dùng tài liệu

- Tài liệu Endless là nguồn yêu cầu hiện hành cho card draft, endless, flood, hạ tầng, camera và gameplay UI.
- Tài liệu Xe dân được dùng làm mẫu về cách viết checklist, đầu ra và quy trình bàn giao. Các phần Shop, giá tiền, phân công cũ hoặc trạng thái hoàn thành trong đó không tự động trở thành yêu cầu mới.
- Đây là phân công cho prototype, không phải báo cáo tiến độ. Các tên B/C/D/E là owner theo vai trò; dùng branch gợi ý bên dưới nếu chưa có branch khác được nhóm thống nhất.
- B và E phụ trách những phần cần tinh chỉnh giao diện. B là owner chính về tính nhất quán hình ảnh/gameplay HUD; E phụ trách card draft và phần hiển thị/camera được tách riêng bên dưới.
- C và D nhận các module gameplay có ranh giới/API rõ để có thể dùng AI hỗ trợ triển khai nhanh. Việc dùng AI không thay thế review, test hoặc kiểm tra tích hợp.
- Dùng hợp đồng runtime và prototype defaults trong tài liệu này để bắt đầu mà không cần hỏi nhau về tên signal, payload, inventory owner hay các giá trị khởi đầu. Nếu phát hiện source không khớp, đề xuất thay đổi trong PR và báo các owner liên quan; không âm thầm tạo hợp đồng thứ hai.

## 2. Chia ownership tổng quan

| Thành viên | Vai trò chính | Phần sở hữu |
|---|---|---|
| **B** | UI/UX owner, chú trọng chi tiết | Gameplay HUD, toolbar, nút Vẽ/Xóa, đồng hồ Pause/tốc độ, cảnh báo, trạng thái thất bại, chuẩn hình ảnh chung và review UI. |
| **E** | Card UI và camera/viewport | Màn hình chọn card, trình bày reward trong card, layout card ở 16:10, camera zoom theo con trỏ và nền đệm. B sở hữu inventory count trên toolbar. |
| **C** | Gameplay progression backend | Endless wave, mốc sống sót ba wave, trạng thái kết thúc, card generation/reward model, inventory reward và điểm; không sở hữu scene/UI. |
| **D** | Flood, graph và chuyển động | Độ sâu lũ theo vùng, boat navigation mask, hệ thống đặt hạ tầng trong graph và gia tốc/phanh; không sở hữu HUD/card presentation. |

### Quy tắc ownership file

- B sở hữu phần HUD/tool selection và các scene/nút điều khiển gameplay. E không chỉnh các file đó nếu không thống nhất với B.
- E sở hữu card draft UI, `game/stage_view.gd` và cấu hình viewport/camera. B góp ý style/layout, không đồng thời sửa cùng file.
- C sở hữu logic wave/card/reward/inventory và trạng thái run. C không làm layout UI.
- D sở hữu logic flood/graph/edge/vehicle movement và dữ liệu điều hướng liên quan. D không làm layout UI.
- `autoload/config.gd` là file dùng chung: C sở hữu phần wave/reward; D sở hữu phần flood/vehicle. Báo nhau trước khi sửa và tránh merge đồng thời hai thay đổi trên cùng file.
- `autoload/event_bus.gd`, `ui/ui_root.gd`, `project.godot` và scene dùng chung là file giao diện giữa các workstream. Chỉ sửa sau khi owner liên quan thống nhất API và báo trước cho nhau.

### Hợp đồng giữa các workstream

- **C sở hữu dữ liệu run và inventory:** số lượng item, reward payload, wave state, trạng thái draft và lựa chọn card. E hiển thị offer và gửi lựa chọn; B đọc inventory để vẽ số lượng trên toolbar.
- **D sở hữu luật graph/placement:** xác định vị trí đặt hợp lệ, tạo/xóa graph item và báo kết quả. D không tạo một bản inventory riêng; phải dùng API inventory do C cung cấp. Placement không hợp lệ không được tiêu thụ item; đặt hợp lệ chỉ tiêu thụ một lần.
- Cần thống nhất thứ tự xử lý placement để tránh mất item nếu thao tác graph thất bại giữa chừng. D và C ghi rõ API/transaction/error behavior trước khi UI nối vào.
- **Refund đã xác nhận:** đèn khi junction bị phá/xóa; highway khi người chơi xóa tuyến. **Mặc định prototype thêm:** refund roundabout/Ferry khi người chơi chủ động xóa; không refund lần nữa chỉ vì flood tạm khóa tuyến hoặc hệ thống tự fallback. D bảo đảm idempotency bằng cách chỉ refund sau khi xóa graph thành công; thao tác xóa lặp lại trả failure và không refund.
- **C sở hữu việc đóng băng/thả simulation** khi vào/thoát draft. E chỉ mở/đóng view theo state hoặc gọi API đã thống nhất; UI không tự giữ một cờ pause thứ hai.
- Các mặc định prototype bên dưới được nhóm tự triển khai và có thể chỉnh sau playtest; không cần chờ Lead duyệt từng con số nhỏ. Nếu thay hướng thiết kế đã nêu, ghi rõ lý do và báo Lead.

### File dự kiến theo owner

Đây là ranh giới dự kiến, cần đối chiếu source trước khi sửa vì file/scene có thể thay đổi:

- **B:** `ui/hud.gd`, `ui/tool_bar.gd`, các scene điều khiển gameplay; `ui/ui_root.gd` chỉ sửa sau khi E báo event/callback cần ghép.
- **E:** `ui/reward_popup.gd`, `ui/reward_popup.tscn` để thay/gỡ shop và làm card draft; phần card trong `ui/ui_root.gd` sau khi thống nhất với B; `game/stage_view.gd`, cấu hình viewport/camera trong `project.godot`.
- **C:** `autoload/types.gd`, `autoload/config.gd` cho wave/reward, `autoload/event_bus.gd`, `autoload/game_manager.gd`, `game/score_system.gd` và test liên quan.
- **D:** phần flood/vehicle trong `autoload/config.gd`, `flood/flood_manager.gd`, `graph/graph_manager.gd`, `graph/edge.gd`, `rescue/rescue_manager.gd`, dữ liệu map/nav và test Flood/Boat/Traffic.
- Thay đổi file dùng chung không thuộc quyền độc quyền của một người nếu hợp đồng chưa thống nhất. Báo owner trước, chia PR hoặc chọn một người tích hợp để tránh conflict.

### Hợp đồng runtime dùng chung — dùng đúng tên/payload này cho prototype

#### ID dùng chung

- Giữ nguyên giá trị hiện có trong `Types.Reward`: `MORE_EDGES=0`, `EXTRA_TRUCK=1`, `EXTRA_BOAT=2`, `UPGRADE_TRUCK_CAP=3`, `UPGRADE_BOAT_CAP=4`. Chỉ nối thêm `TRAFFIC_LIGHT=5`, `ROUNDABOUT=6`, `HIGHWAY=7`, `FERRY=8`.
- `Types.VehicleType`: `TRUCK=0`, `BOAT=1`, `MOTORBIKE=2`, `CAR=3`. D thay local magic numbers `2/3` trong `RescueManager` bằng enum sau khi C thêm các giá trị.
- Thêm `Types.ToolId`: `ROAD=0`, `FERRY=1`, `TRAFFIC_LIGHT=2`, `ROUNDABOUT=3`, `HIGHWAY=4`, `ERASE=5`. Các số này là tool selection, không phải slot index trên toolbar.

#### Card draft và wave lifecycle

- C sở hữu `GameManager` state. Thêm `Types.GameState.CARD_DRAFT`; dùng `EventBus.game_state_changed(state)` hiện có để báo UI.
- C phát `EventBus.card_offers_ready(offers: Array)` khi draft mở. Mỗi offer là Dictionary:
  - `id: StringName` — duy nhất trong draft hiện tại.
  - `title: String` — tên ngắn để hiển thị.
  - `icon_key: StringName` — khóa icon ổn định để UI tra theme/resource.
  - `rewards: Array[Dictionary]` — mỗi phần tử có `reward_id: int` và `amount: int`.
- E chỉ render payload và gọi `GameManager.choose_card(card_id: StringName) -> bool`. Không tự cấp reward, pause hoặc bắt đầu wave.
- C sở hữu các API: `GameManager.get_card_offers() -> Array`, `GameManager.choose_card(card_id: StringName) -> bool`, `GameManager.get_inventory(reward_id: int) -> int`, `GameManager.grant_reward(reward_id: int, amount: int) -> bool`, `GameManager.try_consume_item(reward_id: int, amount: int = 1) -> bool`, `GameManager.refund_item(reward_id: int, amount: int = 1) -> void`.
- C phát signal mới `EventBus.inventory_changed(reward_id: int, available: int)` sau khi grant/consume/refund. EventBus chỉ khai báo signal; GameManager phát signal.
- C khai báo `EventBus.edge_budget_changed(used: int, limit: int)` trong EventBus; D/GraphManager phát sau khi thêm/xóa đường hoặc đổi giới hạn. B đọc signal này và chỉ đọc inventory API cho token đặt được.
- Khi cấp `MORE_EDGES`, C gọi `GraphManager.add_edge_limit(amount)`; D cập nhật giới hạn và phát `edge_budget_changed`.
- Dùng `EventBus.card_offers_ready` cho UI draft mới; chuyển tất cả listener khỏi `reward_offered(options)` và `reward_chosen(reward)` rồi ngừng phát signal Shop cũ.
- `start_game()` mở draft đầu tiên trước wave 1. Kết thúc mỗi wave mở draft ngay; game đứng yên trong suốt lựa chọn; sau khi chọn hợp lệ thì bắt đầu wave tiếp theo ngay. Draft thay toàn bộ thời gian nghỉ/shop 15 giây, không có countdown nghỉ chạy ngầm.
- `GameManager` giữ wave index 0-based để tương thích `wave_started(index)`; `Config.get_wave_profile(wave_number: int) -> Dictionary` nhận số wave 1-based. Dictionary luôn có các khóa `water_peak`, `sos_interval`, `sos_max`, `sos_units`, `house_interval`, `food_ratio`, `deadline_food`, `deadline_medical`. Dùng cùng profile ở FloodManager và RescueManager, không truy cập trực tiếp `Config.WAVES[index]`.
- Wave 1–3: sau khi kết thúc wave thứ ba, mở draft/endless tiếp tục chứ không phát `game_won`. Thua trước mốc đó là `LOST`; thua sau khi đã hoàn tất wave 3 là `WON` theo màn hình kết quả hiện tại.

#### Inventory, budget và placement transaction

- GameManager là nguồn inventory duy nhất cho token traffic light, roundabout, highway và Ferry. Dọn bộ đếm Ferry riêng trong GraphManager; nếu cần tương thích call site cũ thì giữ getter wrapper chỉ đọc từ GameManager, không giữ bản sao số lượng.
- Road không phải token placement: reward `MORE_EDGES` gọi `GraphManager.add_edge_limit(amount)`. Số đường còn lại lấy từ `EventBus.edge_budget_changed(used, limit)`; B không đọc inventory cho số đường.
- `EXTRA_TRUCK`/`EXTRA_BOAT` thêm số xe tương ứng; capacity upgrade đặt sức chứa lên 2 một lần. Đây không phải token toolbar.
- B đọc số lượng bốn token đặt được bằng `GameManager.get_inventory(reward_id)`. D không tự giữ hoặc giảm count ở GraphManager/RescueManager.
- Placement flow thống nhất: UI gọi API placement của GraphManager; GraphManager validate đầy đủ trước, gọi `GameManager.try_consume_item()`, commit graph; nếu commit thất bại thì gọi `refund_item()` và trả failure. Placement invalid không làm thay đổi graph hoặc inventory.
- Với item được hoàn theo baseline ở trên, GraphManager chỉ gọi `refund_item()` sau khi xóa graph thành công. Đèn chỉ hoàn khi junction chứa nó bị xóa; highway/roundabout/Ferry hoàn khi người chơi chủ động xóa. Xóa lại cùng item phải trả failure, không refund lần hai. Flood tạm khóa tuyến hoặc auto-fallback không tính là người chơi xóa.
- Cập nhật các signal/tool consumer cũ (`ferry_inventory_changed`, các count tĩnh trong toolbar) sang `inventory_changed`; chỉ giữ compatibility shim nếu cần trong cùng PR migration, không cho hai signal cùng là nguồn dữ liệu chuẩn.

#### Graph/placement API D cung cấp cho UI

Các method placement trả `bool` để UI biết thao tác thành công; preview/validation không tiêu thụ inventory:

- `GraphManager.can_place_traffic_light(junction_id: int) -> bool` / `place_traffic_light(junction_id: int) -> bool`
- `GraphManager.can_place_roundabout(junction_id: int) -> bool` / `place_roundabout(junction_id: int) -> bool`
- `GraphManager.remove_roundabout(junction_id: int) -> bool`
- `GraphManager.get_highway_preview_points(start: Vector2i, end: Vector2i) -> PackedVector2Array`
- `GraphManager.can_place_highway(start: Vector2i, end: Vector2i) -> bool` / `place_highway(start: Vector2i, end: Vector2i) -> int` (route ID; `-1` nếu thất bại)
- `GraphManager.remove_highway(route_id: int) -> bool`
- `GraphManager.add_edge_limit(amount: int) -> void` / `get_edge_budget() -> Dictionary` (`used: int`, `limit: int`); phát `edge_budget_changed` sau mỗi thay đổi.
- Giữ API Ferry hiện có `can_place_ferry(cell_a, cell_b)`, `place_ferry(cell_a, cell_b)` và `remove_ferry_at_cell(cell)`; kết quả placement/removal phải báo success/failure, thay phần kiểm tra/consume/refund token để dùng GameManager.
- `GraphManager.cell_is_boat(cell)` chỉ nói ô thuộc nước cố định trong map. D thêm `GraphManager.is_boat_route_cell(cell)` cho mask điều hướng cố định (sông + kênh được đánh dấu); độ sâu/đóng mở cạnh vẫn do flood state quyết định.
- Placement input: B chọn tool qua `EventBus.active_tool_changed(tool_id)`; Road/Erase dùng kéo; Ferry chọn hai bờ; traffic light/roundabout click junction; highway chọn đầu, xem preview khi rê chuột, chọn cuối. Chuột phải hoặc Escape hủy placement đang diễn ra.

#### Tuning và kết quả cứu hộ

- C sở hữu `Config.get_wave_profile()` và toàn bộ giá trị profile theo wave, gồm `water_peak`; D sở hữu công thức flood depth, điều hướng và movement trong Config, đồng thời cung cấp số đo. D không sửa wave profile nếu chưa phối hợp C.
- D cung cấp `RescueManager.has_rescue_route(node_id: int) -> bool`; SOS thường chỉ được sinh nếu có ít nhất một route tới node bằng phương tiện hiện có. Nhiệm vụ không có route chỉ được thêm sau khi có luật đặc biệt riêng.
- `EventBus.sos_rescued(req_id, points)` tiếp tục là sự kiện hoàn tất SOS; C/ScoreSystem đặt `points = 1` mỗi SOS hoàn thành và loại quỹ/shop khỏi luồng reward.

## 3. NGƯỜI B — Owner UI gameplay và hoàn thiện trải nghiệm

**Độ ưu tiên:** Cao. Đây là phần cần sự nhất quán về khoảng cách, căn lề, trạng thái hover/selected và khả năng đọc nhanh.
**Nhánh chuẩn:** `feat/endless-ui-b`

### Mục tiêu

Tạo UI trong trận tối giản, tối màu, ưu tiên icon và trạng thái trực quan. UI phải hoạt động tốt ở viewport 16:10 nhưng không kéo giãn map 16:9.

### Checklist công việc

- [ ] Đọc lại HUD/toolbar hiện có và ghi rõ các control giữ lại, bỏ đi, hoặc cần chuyển vị trí trước khi sửa scene.
- [ ] Thiết lập layout gameplay HUD: điểm +1 mỗi SOS cứu thành công; bỏ hiển thị quỹ/shop, số wave và số SOS thất bại dạng số.
- [ ] Biểu thị số lần thất bại bằng tối đa ba chấm/icon nhỏ, vẫn phân biệt rõ chưa dùng/đã dùng và trạng thái thua.
- [ ] Thiết kế toolbar vật phẩm ở chính giữa cạnh dưới:
  - Chỉ hiện khi con trỏ đến vùng toolbar.
  - Tự ẩn khi con trỏ rời vùng.
  - Không tự ẩn khi đang đặt vật phẩm hoặc chọn card/item.
  - Đọc count của traffic light/roundabout/highway/Ferry từ `GameManager.get_inventory(reward_id)`.
  - Đọc snapshot đầu tiên từ `GraphManager.get_edge_budget()`, sau đó cập nhật theo `edge_budget_changed(used, limit)`; road budget không phải inventory token.
  - Đọc inventory ban đầu qua `get_inventory(reward_id)`, sau đó cập nhật theo `inventory_changed`.
  - Disable item placement khi count bằng 0; UI không tự trừ/refund count.
- [ ] Dùng `Types.ToolId` thống nhất: ROAD=0, FERRY=1, TRAFFIC_LIGHT=2, ROUNDABOUT=3, HIGHWAY=4, ERASE=5. `active_tool_changed` vẫn dùng signal hiện có.
- [ ] Tạo lựa chọn Vẽ và Xóa ở cạnh phải:
  - Chế độ Xóa dùng click/kéo.
  - Giữ chuột phải làm shortcut nếu không xung đột với thao tác hiện tại.
  - Trạng thái đang chọn phải dễ nhận ra nhưng không che map.
- [ ] Gom Pause/Play và tốc độ x1/x2/x3 thành điều khiển đồng hồ gọn; không mở modal pause lớn khi chỉ pause.
- [ ] Tạo mũi tên góc trên trái để mở các hành động Chơi lại/Menu theo flow hiện tại.
- [ ] Thay banner thường bằng icon/feedback ngắn; cảnh báo lũ/SOS quan trọng phải còn dễ thấy và không phụ thuộc chỉ vào màu.
- [ ] Phối hợp với E để card draft, toolbar và các popup dùng chung font, màu, icon, viền, spacing và trạng thái focus/disabled.
- [ ] Kiểm tra UI ở 1920×1200 và ít nhất một viewport khác; đảm bảo map không bị kéo giãn, control không tràn và toolbar không che vùng cần thao tác.

### Đầu ra

- Gameplay HUD/toolbar/control đã được cập nhật theo layout thống nhất với E.
- Danh sách tương tác bằng chuột và trạng thái UI trong mô tả PR.
- Ảnh kiểm tra hoặc bản ghi bước tái hiện cho các trạng thái chính: bình thường, toolbar hover, đặt item, Xóa, pause, cảnh báo và gần hết số lần thất bại.

### Không thuộc phạm vi của B

- Không sửa logic card/wave/inventory để làm UI hiển thị đúng; báo C/E về API còn thiếu.
- Không thay đổi luật điểm, điều kiện thắng/thua, flood hoặc graph.
- Không thêm bộ đếm xe dân, wave hoặc SOS failed dạng số trở lại HUD nếu chưa được Lead duyệt.

### Definition of done

- Layout và input được B kiểm tra trực tiếp trong game, không chỉ dựa vào mở scene trong editor.
- Trạng thái hover/đang chọn/đang đặt/disabled đọc được; UI vẫn dùng được trong lúc game chạy nhanh và khi pause.
- Test các thao tác chuột chính không chặn vẽ/xóa đường hoặc đặt item.
- Không thêm asset/code từ game tham khảo.

## 4. NGƯỜI E — Card draft UI, inventory presentation và camera/viewport

**Độ ưu tiên:** Cao; card screen là điểm vào mỗi wave, còn viewport/camera ảnh hưởng toàn bộ layout.
**Nhánh chuẩn:** `feat/endless-card-camera-e`

### Mục tiêu

Hiển thị rõ bốn card và lựa chọn hiện tại mà không biến draft thành shop nhiều chữ; đặt map 16:9 trong viewport 16:10 và zoom theo con trỏ.

### Checklist công việc

- [ ] Làm UI draft trước wave đầu và giữa mỗi wave, dùng dữ liệu offer do C cung cấp.
- [ ] E sở hữu việc thay luồng shop cũ bằng card draft trong `ui/reward_popup.gd` và `ui/reward_popup.tscn`; phối hợp C để bỏ signal/backend shop và cập nhật chỗ nối trong `ui/ui_root.gd`.
- [ ] Hiển thị đúng bốn card khác nhau; mỗi card có icon, tên ngắn, phần thưởng và số lượng đủ để người chơi hiểu gói mình nhận.
- [ ] Hỗ trợ hover/focus/selected/disabled rõ ràng; tránh cho phép chọn hai card hoặc double-click cấp thưởng hai lần.
- [ ] Khi người chơi chọn card, gửi đúng ID card cho C; không tự cộng inventory hoặc tự tính xác suất ở UI.
- [ ] Nghe `EventBus.card_offers_ready(offers)`; mỗi offer đọc `id`, `title`, `icon_key`, `rewards[{reward_id, amount}]`. `icon_key` dùng đúng template key trong bảng card baseline mục 7. Khi panel mở, gọi `get_card_offers()` để đồng bộ snapshot nếu đã lỡ event. Nút chọn gọi duy nhất `GameManager.choose_card(id)`.
- [ ] Card panel dùng `PROCESS_MODE_ALWAYS` để thao tác được khi SceneTree pause; không tự giữ pause flag. C phát state đổi và unpause sau khi nhận lựa chọn hợp lệ.
- [ ] Card UI phải xử lý reward nhiều thành phần, số lượng tăng theo wave và upgrade đã max/không còn hợp lệ theo payload backend.
- [ ] Cùng B thống nhất bộ style; E sở hữu cấu trúc và layout của card panel, B là người review tính nhất quán với HUD.
- [ ] Chuyển viewport mục tiêu sang 16:10, 1920×1200:
  - Map 16:9 nằm giữa và không bị kéo giãn.
  - Phần viewport dư có nền phù hợp.
  - UI dùng anchors/container theo viewport thay vì rải thêm tọa độ cố định 1280×720.
- [ ] Thêm zoom bằng con lăn, zoom hướng về vị trí con trỏ; mức nhỏ nhất cho thấy toàn map.
- [ ] Dùng max zoom prototype 2× mức fit-map; giữ trong một config/constant để tune, chưa thêm pan.

### Đầu ra

- Card draft UI được nối với API của C.
- Camera/viewport hoạt động ở mục tiêu 16:10, có zoom theo con trỏ.
- Hướng dẫn ngắn trong PR về cách kiểm tra draft, card bundle, zoom min/max và map nền đệm.

### Không thuộc phạm vi của E

- Không tự quyết định xác suất/rank card, phần thưởng hoặc luật endless.
- Không tự cộng/trừ inventory, điểm hay quỹ trong UI.
- Không thay đổi HUD/toolbar do B sở hữu nếu chưa phối hợp.

### Definition of done

- Không thể bỏ qua lựa chọn card để thời gian wave tiếp tục chạy; chỉ một lựa chọn được áp dụng.
- Mọi reward payload hợp lệ từ C đều hiển thị; dữ liệu thiếu được báo lỗi rõ, không hiện card thành công nhưng rỗng.
- Zoom đúng quanh con trỏ và giữ map không méo ở cả zoom nhỏ nhất lẫn lớn nhất.
- UI được kiểm tra ở 1920×1200 và ở viewport khác để tránh phụ thuộc cứng vào một độ phân giải.

## 5. NGƯỜI C — Card/reward backend và vòng đời endless

**Độ ưu tiên:** Làm API/state trước để E có thể nối UI và các feature item có thể nhận inventory.
**Nhánh chuẩn:** `feat/endless-core-c`

### Mục tiêu

Thay shop/tiền mua bằng reward card; hỗ trợ wave sau wave 3 mà không truy cập vượt mảng; giữ rõ khác biệt giữa thua trước và sau mốc endless.

### Checklist công việc

- [ ] Thiết kế model dữ liệu cho một card offer, gồm ID ổn định trong lượt, tiêu đề/icon key, danh sách phần thưởng và số lượng.
- [ ] Giữ `Types.Reward` ID 0–4 như source; nối thêm traffic light, roundabout, highway, Ferry lần lượt 5–8. Giữ `Types.VehicleType` 0/1 hiện tại, nối MOTORBIKE=2 và CAR=3; thêm `Types.ToolId` theo hợp đồng ở mục 2.
- [ ] Thêm `Types.GameState.CARD_DRAFT` ở cuối enum để giữ nguyên ID state cũ.
- [ ] Viết hàm tạo bốn card khác nhau cho mỗi draft:
  - Dùng đúng catalog, trọng số và hệ số số lượng ở mục 7; rút bốn template không hoàn lại theo trọng số hiệu lực.
  - Không bảo đảm mỗi nhóm reward luôn xuất hiện; chỉ bỏ template chứa upgrade đã max khỏi pool.
  - Mỗi template chỉ xuất hiện tối đa một lần trong cùng draft; có thể xuất hiện lại ở draft sau.
  - Một card có thể cấp nhiều loại phần thưởng.
  - Prototype chưa đặt hard cap cho token tiêu hao; không đưa upgrade một lần nữa vào pool nếu người chơi đã đạt mức tối đa của upgrade đó.
  - Dùng seed hoặc dependency có thể kiểm soát để test được; không làm random test không ổn định.
- [ ] Thêm flow draft trước wave đầu và giữa các wave; có trạng thái rõ ràng `awaiting_choice`/đã chọn.
- [ ] Đóng băng mô phỏng trong khi chờ card; chỉ bắt đầu wave sau khi một lựa chọn hợp lệ được xác nhận.
- [ ] Chặn chọn trùng/nhiều lần và bảo đảm reward chỉ được cấp đúng một lần.
- [ ] Tạo API/event cho E đọc danh sách offer, chọn card và nhận inventory/reward result. Ghi rõ payload và error case.
- [ ] Cài đúng API chung: `get_card_offers()`, `choose_card(card_id)`, `get_inventory(reward_id)`, `grant_reward(reward_id, amount)`, `try_consume_item(reward_id, amount)` và `refund_item(reward_id, amount)`.
- [ ] Thêm signal declaration `card_offers_ready(offers: Array)` và `inventory_changed(reward_id: int, available: int)` vào EventBus; GameManager là nơi emit. Chuyển UI listener sang signal mới, rồi ngừng dùng `reward_offered` và `reward_chosen`.
- [ ] Chuyển quyền sở hữu count Ferry về GameManager. `GraphManager` không giữ count thứ hai; nếu giữ `get_ferries_available()` tạm thời thì chỉ forward sang GameManager.
- [ ] Khi cấp `MORE_EDGES`, gọi `GraphManager.add_edge_limit(amount)`; không biến road budget thành inventory token.
- [ ] Thay truy cập trực tiếp `Config.WAVES[index]` bằng hàm/cấu hình wave dùng được sau wave 3.
- [ ] Xử lý milestone:
  - Thua trước khi sống sót qua ba wave đầu: kết quả thua.
  - Sống sót qua wave 3: tiếp tục endless.
  - Thua sau milestone: dùng end screen chiến thắng hiện tại.
- [ ] Tạo `endless_profile` có tham số tập trung, không truy cập vượt mảng wave:
  - Tính `pressure_tier = floor((wave_number - 4) / 2) + 1` cho wave 4 trở đi (`wave_number` bắt đầu từ 1).
  - Áp dụng chính xác các công thức SOS, nhà, deadline và mực nước trong mục 7; wave 1–3 giữ nguyên dữ liệu `Config.WAVES`.
  - Không thêm traffic spawner hoặc field traffic giả định vào profile: hiện chưa có cơ chế spawn xe dân theo wave trong source; báo B/E và người dùng nếu prototype cần mở rộng scope đó.
- [ ] Cung cấp `Config.get_wave_profile(wave_number)` với các key dùng chung được ghi trong mục 2; wave_number là 1-based. Dùng cấu hình này làm nguồn duy nhất cho FloodManager và RescueManager.
- [ ] Khi wave kết thúc, mở CARD_DRAFT ngay; không chạy 15 giây break sau lưng panel. Chọn xong mới bắt đầu wave kế tiếp; wave 3 kết thúc cũng draft tiếp tục endless.
- [ ] Đặt hệ số/giới hạn theo mục 7 thành hằng số dễ tuning; kiểm tra ít nhất tới wave 8 rồi ghi lại số liệu trước khi đề xuất chỉnh.
- [ ] Bỏ luồng mua bằng quỹ và giá shop. Điểm cứu hộ là +1 mỗi SOS thành công, không còn dùng điểm/quỹ đó để mua reward.
- [ ] Cung cấp API cộng inventory cho road, truck/boat capacity, traffic light, roundabout, highway và Ferry; không gắn logic cấp item vào card UI.
- [ ] Làm rõ với D hợp đồng tiêu thụ/hoàn item để placement không trừ hai lần hoặc mất token khi thao tác thất bại.
- [ ] Đặt quy tắc reset state khi restart run để không giữ card, inventory, wave index hoặc milestone từ run cũ.

### Test cần có

- [ ] Draft đầu ván và draft giữa wave đều dừng simulation; chọn một card mới tiếp tục.
- [ ] Một draft không có offer/reward bundle giống hệt offer khác; card bundle cấp đủ tất cả reward đã khai báo.
- [ ] Chọn hai lần hoặc gửi ID không tồn tại không cấp thưởng lần hai và không làm game chuyển sang trạng thái thành công giả.
- [ ] Wave 0–2 giữ đúng milestone; wave index lớn hơn 2 không gây out-of-range.
- [ ] Thua trước/sau milestone cho đúng end state.
- [ ] Assert profile chính xác ở wave 4, 6, 8 và 18 (giá trị tier/cap trong mục 7); wave 1–3 không đổi.
- [ ] Assert amount scale 1 ở draft đầu/wave 4, scale 2 ở draft wave 8, scale 3 từ draft wave 12; capacity upgrade luôn amount 1 và không xuất hiện sau khi đã max.
- [ ] Restart reset đầy đủ trạng thái.
- [ ] Card generation có test xác định được bằng seed; không assert xác suất ngẫu nhiên dựa trên một lượt test đơn.

### Không thuộc phạm vi của C

- Không dựng card panel/HUD hoặc điều chỉnh bố cục.
- Không quyết định thông số cân bằng cuối cùng cho mực nước, độ sâu hay gia tốc.
- Không tự thêm xe dân cá nhân hoặc multi-carry nếu feature đó không nằm trong source/plan hiện hành và chưa được Lead xác nhận.

### Definition of done

- API và state transition được mô tả trong PR trước khi E nối giao diện.
- Test tự động tập trung vào state, chọn card, cấp reward, reset và milestone.
- Không có tham chiếu vượt mảng wave sau wave 3; lỗi input được thông báo/ghi nhận theo convention của project.

## 6. NGƯỜI D — Flood/boat graph, item placement và chuyển động xe

**Độ ưu tiên:** Chia thành các mốc riêng; không gộp toàn bộ graph, flood và acceleration vào một PR lớn.
**Nhánh chuẩn:** `feat/endless-graph-flood-d`

### Mục tiêu

Giữ lũ có ý nghĩa chiến thuật, hạn chế ca-nô đi xuyên mọi ô phố sâu, và cung cấp graph/gameplay support cho hạ tầng đặt được.

### Mốc D1 — Flood depth và boat navigation

- [ ] Tách trạng thái “ô đang ngập/độ sâu” khỏi trạng thái “ca-nô được đi qua”.
- [ ] Dùng mặc định prototype: vùng sâu tối đa ba ô theo khoảng cách thủy văn từ sông/kênh; chỉ mở tới ô thứ tư nếu là vùng trũng liên thông. Phía sâu trong đất liền chủ yếu bị giới hạn ở ngập vừa.
- [ ] Không dùng vòng tròn/bán kính tuyệt đối làm luật duy nhất; tính đến địa hình, vùng trũng, kết nối nguồn nước và vật cản. Ngoại lệ phải được khai báo rõ trong dữ liệu map.
- [ ] Chỉ sông và các hành lang được đánh dấu trong dữ liệu map mở cho ca-nô. Không tự thêm mọi ô phố ngập sâu vào boat graph.
- [ ] Giữ logic trạng thái đường: xe tải đi chậm ở ngập vừa, bị chặn ở ngập sâu; các tuyến đất cao/đường cao tốc cần có thể duy trì kết nối land-route theo hướng thiết kế.
- [ ] Phối hợp C/Lead về tham số Config; không tự đặt thêm wave peak hoặc thay đổi toàn bộ map khi chưa có prototype.
- [ ] Tạo log/debug view hoặc cách đo để so sánh diện tích khô/vừa/sâu và thành phần liên thông của land-route, boat-route theo wave.
- [ ] Giữ ít nhất một land backbone nối hub với vùng đất liền trong pha nước cao. Không cần mọi SOS đi được bằng đường bộ, nhưng SOS thường phải có route bằng ít nhất một phương tiện hiện có.
- [ ] Cung cấp `RescueManager.has_rescue_route(node_id: int) -> bool` để C chỉ sinh SOS thường tại node có route bằng phương tiện hiện có.
- [ ] Báo cáo số liệu/map minh họa sau prototype; không chờ Lead duyệt từng giá trị vùng sâu trước khi triển khai.

**Kiểm thử D1**

- [ ] Ô ngập sâu ngoài nav mask không tạo route cho ca-nô.
- [ ] Sông/hành lang đánh dấu có thể đi khi trạng thái nước hợp lệ và đóng/mở đúng theo độ sâu.
- [ ] Các wave lớn có vùng sâu gần sông và phần đất liền chủ yếu ngập vừa; kiểm tra trên map hiện tại.
- [ ] Đo land-route còn liên thông ở từng giai đoạn; SOS thường không được sinh ở vị trí không thể tiếp cận bằng đội xe hiện có.

### Mốc D2 — Hạ tầng đặt được trong graph

- [ ] Cung cấp đúng API `can_place_*`/`place_*`/`remove_*` trong hợp đồng mục 2; validation/preview không tiêu thụ, API `place_*` tự tiêu thụ đúng một item sau validation thành công và chỉ commit graph nếu transaction thành công.
- [ ] Với inventory, gọi API của C theo hợp đồng đã thống nhất; không tự tăng/giảm token trong GraphManager hoặc RescueManager.
- [ ] Cấp `GraphManager.add_edge_limit(amount)` và `get_edge_budget()`; phát `EventBus.edge_budget_changed(used, limit)` sau khi đường được thêm/xóa hoặc budget đổi.
- [ ] Gỡ luật tự tạo/cấp miễn phí đèn giao thông theo số nhánh junction hiện tại. Junction từ ba nhánh trở lên chỉ có đèn nếu người chơi đã đặt item đèn; traffic light không được tự sinh từ hình học.
- [ ] Traffic light đặt tại junction có ít nhất ba nhánh; graph xử lý luồng xe theo pha/quyền đi; nếu junction bị phá thì hoàn item.
- [ ] Roundabout item tự tạo footprint 3×3 tại junction có 3–4 nhánh, nối lại các nhánh hợp lệ và áp dụng luồng một chiều theo chiều kim đồng hồ. Nếu footprint bị chặn/không đủ chỗ thì placement invalid; vòng đường tự vẽ không tự thành roundabout.
- [ ] Junction thường không nhận bonus vòng xoay; xe giảm tốc/nhường theo rule chung.
- [ ] Highway tạo một tuyến mỗi token; hai endpoint gắn lên đường, có route riêng trên cao, không sinh junction tại chỗ giao cắt mặt đất. Prototype không đặt giới hạn chiều dài riêng ngoài biên map và endpoint hợp lệ.
- [ ] Bắt đầu với tốc độ highway 1.5× tốc độ đường thường; đặt trong Config để cân bằng sau test.
- [ ] Highway dùng được cho xe cứu hộ và phương tiện đường bộ; xóa tuyến hoàn token.
- [ ] Ferry tiếp tục dùng hệ thống tuyến qua sông hiện có, nhưng inventory/token phải nhận được từ reward backend của C.
- [ ] Refund theo đúng baseline mục 2: đèn khi junction bị xóa; highway/roundabout/Ferry khi người chơi chủ động xóa; không refund lặp lại khi route bị flood tạm khóa hoặc tự fallback.
- [ ] Công bố API/điều kiện placement cho B/E để UI chỉ hiển thị preview và gọi placement, không tự thao tác graph.

**Kiểm thử D2**

- [ ] Item không bị trừ khi placement invalid; chỉ trừ đúng một lần khi placement thành công.
- [ ] Xóa junction có traffic light hoàn đúng một item.
- [ ] Junction đủ nhánh nhưng chưa được đặt item không tự có traffic light; đặt item thành công mới bật cơ chế đèn.
- [ ] Đặt/xóa roundabout giữ kết nối graph theo rule và không làm vòng đường thường tự đổi hướng.
- [ ] Highway không tạo junction mặt đất tại giao cắt; route pathfinding dùng được cho loại xe được phép.
- [ ] Xóa highway hoàn một token; thao tác lặp không nhân token.
- [ ] Xóa roundabout/Ferry theo thao tác chủ động hoàn đúng một token; flood/fallback không tự hoàn token.

### Mốc D3 — Gia tốc và phanh phương tiện

- [ ] Áp dụng gia tốc/phanh riêng theo từng loại phương tiện hiện có.
- [ ] Xe tăng tốc rời trạng thái dừng; giảm tốc trước junction cần nhường/dừng, đích, bến phà và hàng chờ.
- [ ] Giữ current speed qua các cạnh/ô liền mạch; không reset tốc độ mỗi khi chuyển tile.
- [ ] Tôn trọng tốc độ tối đa, loại cạnh, độ sâu lũ, traffic congestion và dừng hoàn toàn khi cần.
- [ ] Đưa thông số gia tốc/phanh riêng từng loại xe vào phần movement của Config; dùng giá trị khởi đầu bảo thủ để xe dừng được trước điểm dừng, rồi tune sau test. Không hard-code hằng số rải rác trong `Vehicle.advance()`.

**Kiểm thử D3**

- [ ] Xe xuất phát từ tốc độ 0 và đạt giới hạn tốc độ hợp lệ.
- [ ] Xe không vượt quá điểm dừng/target vì phanh không đủ.
- [ ] Chuyển cạnh liên tục không tạo giật tốc độ; xe chậm/đứng đúng khi gặp hàng chờ hoặc junction.
- [ ] Các loại xe có phản hồi khác nhau theo cấu hình của chúng.

### Ranh giới và Definition of done của D

- D không sửa HUD/card layout hoặc tự tạo card reward.
- D không tự quyết định con số cân bằng cuối cùng; gửi kết quả đo, video/mô tả tái hiện và đề xuất cho Lead.
- Hoàn tất từng mốc thành PR nhỏ có test tương ứng; không gộp D1–D3 thành một thay đổi không thể review.
- Mỗi API graph/flood dùng bởi UI hoặc C phải được ghi lại và báo cho owner phụ thuộc trước khi merge.

## 7. Mặc định prototype — triển khai trước, cân bằng sau

Các baseline dưới đây dùng cho prototype theo hướng đã chọn. Nhóm có thể chỉnh sau khi kiểm tra build; không cần dừng để xin duyệt từng giá trị ban đầu.

| Chủ đề | Baseline prototype |
|---|---|
| Card pool | Bốn template khác nhau, rút có trọng số không hoàn lại theo catalog bên dưới; reward scale theo tier; token tiêu hao chưa có hard cap; bỏ template upgrade khi đã max. |
| Endless | Wave 1–3 giữ nguyên Config hiện tại. Từ wave 4 dùng pressure tier và công thức cụ thể bên dưới; mực nước đỉnh giữ ở 90, house/SOS pressure và reward tăng dần. Traffic xe dân không được tăng theo wave trong baseline này vì source chưa có traffic spawner theo wave. |
| Độ sâu flood | Deep tối đa ba ô theo khoảng cách thủy văn từ sông/kênh; có thể đến ô thứ tư nếu là vùng trũng liên thông. Phía sâu trong đất liền giới hạn ở shallow, trừ ngoại lệ được đánh dấu trong map data. |
| Boat navigation | Ca-nô đi sông hiện có và mask hành lang được đánh dấu riêng; flood depth không tự tạo boat route. D đề xuất schema mask và cách nối bến/SOS trong PR đầu. |
| Land-route/SOS | Giữ ít nhất một land backbone nối hub với vùng đất liền trong pha nước cao. SOS thường phải có route bằng ít nhất một phương tiện hiện có; không yêu cầu mọi SOS đi được bằng đường bộ. |
| Roundabout | Footprint 3×3, hỗ trợ 3–4 nhánh, chạy một chiều theo chiều kim đồng hồ; invalid nếu không đủ chỗ. Xóa chủ động hoàn một token. |
| Highway | Một token = một route; không giới hạn chiều dài riêng ngoài biên map và endpoint hợp lệ; tốc độ khởi đầu 1.5× đường thường; xóa route hoàn token. |
| Ferry/refund | Xóa Ferry chủ động hoàn token một lần; auto-fallback hoặc flood tạm thời không hoàn token. |
| Gia tốc/phanh | Thông số riêng từng loại xe trong Config; D chọn giá trị khởi đầu bảo thủ để xe dừng được trước điểm dừng, rồi tune sau test. |
| Zoom/UI | Min zoom vừa toàn map; max zoom khởi đầu 2× mức fit-map. Nền đệm xanh-xám/tối, ít tương phản. Mũi tên góc trên trái mở menu nhỏ Restart/Menu, có xác nhận trước hành động làm mất run. |

### Endless profile — giá trị khởi đầu cụ thể

- Wave 1–3 dùng nguyên các Dictionary trong `Config.WAVES`; không đổi profile cũ trong task endless.
- Với `wave_number >= 4`, tính `pressure_tier = floor((wave_number - 4) / 2) + 1`. Mỗi tier kéo dài hai wave: 4–5 là tier 1, 6–7 tier 2, 8–9 tier 3.
- Profile endless dùng các giá trị sau:

| Key | Công thức từ tier `t` | Tier 1 (wave 4–5) | Giới hạn |
|---|---:|---:|---:|
| `water_peak` | `90.0` | 90.0 | Không tăng sau wave 3 |
| `sos_interval` | `max(2.0, 3.8 - 0.3 * t)` | 3.5 s | Tối thiểu 2.0 s |
| `sos_max` | `min(16, 10 + t)` | 11 | Tối đa 16 SOS đang hoạt động |
| `sos_units` | `1` | 1 | Giữ 1 trong prototype |
| `house_interval` | `max(3.0, 5.0 - 0.25 * t)` | 4.75 s | Tối thiểu 3.0 s |
| `food_ratio` | `0.55` | 0.55 | Giữ bằng wave 3 |
| `deadline_food` | `max(18.0, 27.0 - t)` | 26 s | Tối thiểu 18 s |
| `deadline_medical` | `max(14.0, 21.0 - t)` | 20 s | Tối thiểu 14 s |

Giữ `WAVE_DURATION=120`, `WAVE_RISE_TIME=80`, `RECEDE_RATIO=0.45`, `HOUSE_MAX_PER_DISTRICT=3` và `HOUSE_RADIUS=3` như hiện tại. `sos_interval` là nhịp tạo yêu cầu; `sos_max` là số SOS đồng thời. Công thức trên là baseline để chạy prototype, không phải cân bằng cuối.

**Giới hạn traffic:** code hiện có hành vi/kiểu dữ liệu cho xe dân nhưng không có spawner wave-level được cấu hình trong profile hiện tại. Không thêm field traffic không được tiêu thụ hoặc tự tạo luật spawn trong task này; nếu muốn traffic tăng theo wave, cần giao rõ owner và cơ chế spawn riêng.

### Card catalog — số lượng và trọng số khởi đầu

- Draft trước wave 1 dùng tier 1. Draft sau wave kết thúc dùng tier của wave kế tiếp; do đó draft sau wave 3 áp dụng tier 1.
- Chọn bốn template khác nhau, rút không hoàn lại theo trọng số hiệu lực. `id` và `icon_key` dùng cùng key trong bảng. Các trọng số là tỷ lệ tương đối (tổng base weight = 100).
- Khi template chứa `TRAFFIC_LIGHT`, `ROUNDABOUT`, `HIGHWAY` hoặc `FERRY`, trọng số hiệu lực là `base_weight * min(2.0, 1.0 + 0.15 * (t - 1))`; các template khác giữ nguyên base weight. Chuẩn hóa trọng số các template còn khả dụng trước khi rút.
- `amount_scale = min(3, 1 + floor((t - 1) / 2))`. Nhân `amount` của reward lặp lại với hệ số này; không nhân `UPGRADE_TRUCK_CAP`/`UPGRADE_BOAT_CAP` (luôn amount 1). Nếu người chơi đã nâng cấp capacity lên 2, bỏ template chứa upgrade đó khỏi pool.

| `id` = `icon_key` | Base weight | Reward ở tier 1 |
|---|---:|---|
| `road_supply` | 20 | `MORE_EDGES` × 20 |
| `truck_fleet` | 10 | `EXTRA_TRUCK` × 2 |
| `boat_fleet_ferry` | 10 | `EXTRA_BOAT` × 2, `FERRY` × 1 |
| `junction_kit` | 15 | `TRAFFIC_LIGHT` × 1, `ROUNDABOUT` × 1 |
| `highway_ferry` | 15 | `HIGHWAY` × 1, `FERRY` × 1 |
| `boat_capacity` | 10 | `MORE_EDGES` × 20, `UPGRADE_BOAT_CAP` × 1 |
| `truck_capacity` | 10 | `MORE_EDGES` × 20, `UPGRADE_TRUCK_CAP` × 1 |
| `road_highway` | 10 | `MORE_EDGES` × 20, `HIGHWAY` × 1 |

Tất cả card tiêu hao đều có thể xuất hiện lại ở draft sau; trong cùng draft không lặp template. Wave 1–7 dùng amount scale 1; từ wave 8 (tier 3) scale là 2; scale tối đa 3 từ tier 5. Đây là mức khởi đầu có chủ đích để kiểm tra tới ít nhất wave 8 rồi cân bằng lại bằng playtest.

Đây là giá trị thử nghiệm, không phải cân bằng cuối. Ghi lại thông số và kết quả playtest để nhóm điều chỉnh; chỉ hỏi Lead khi muốn đổi hướng thiết kế, thêm luật mới hoặc gặp xung đột giữa hệ thống.

## 8. Nạp context khi dùng AI

Tạo file trong repository không tự đưa nội dung vào mọi AI chat hoặc agent. Hướng dẫn hiện nằm tại `docs/AGENTS.md`; không giả định có `AGENTS.md` ở root. Với AI/subagent khác, hãy gửi prompt rõ ràng và yêu cầu đọc các file liên quan. Agent ở branch/clone khác chỉ đọc được tài liệu nếu các file đã được chia sẻ/commit vào workspace đó hoặc được đính kèm.

### Prompt mẫu dùng chung

```text
Bạn đang làm trong repository Floodline. Trước khi sửa code, hãy đọc:
- docs/AGENTS.md
- docs/endless_gameplay_and_ui_plan.md
- docs/endless_gameplay_team_assignments.md, phần giao việc của bạn là: [B/C/D/E]

Đây là các design doc cho target; hãy kiểm tra source/config/test hiện tại để biết hành vi đã triển khai. FEATURE_XE_DAN_VA_NANG_CAP_XE_CUU_HO.md chỉ là tài liệu giai đoạn cũ/tham khảo format, không dùng làm spec nếu nội dung mâu thuẫn.

Chỉ làm đúng ownership và milestone được giao. Dùng baseline trong mục "Mặc định prototype" để triển khai; các giá trị đó có thể chỉnh sau playtest. Không tự đổi hướng thiết kế hoặc thêm luật ngoài baseline. Trước khi sửa, nêu ngắn gọn các file/API sẽ đụng tới và kiểm tra conflict với owner khác.

Giữ thay đổi trong phạm vi task, cập nhật test phù hợp và chạy test nhỏ nhất bao phủ thay đổi. Khi báo cáo, liệt kê file đã sửa, hành vi đạt được, test đã chạy/kết quả và câu hỏi còn chờ Lead. Không tuyên bố test hoặc review đã chạy nếu chưa chạy.
```

### Phần thêm theo vai trò

- **B:** thêm các trạng thái UI cần hoàn thiện và viewport cần kiểm tra; không sửa logic C/D để bù API thiếu.
- **E:** thêm API card/wave của C đã được thống nhất; không tính reward hoặc giữ state pause riêng trong UI.
- **C:** ghi rõ schema/API mà E và D sẽ dùng; làm test deterministic cho card/wave state.
- **D:** ghi rõ graph/nav/placement API mà B/E/C sẽ gọi; không tự giữ inventory hoặc thay refund policy trong baseline.

## 9. Tạo nhánh, tích hợp và kiểm tra trước khi vào saigon-lu

**Nhánh đích đã kiểm tra trong repository:** `feat/saigon-lu` (gọi tắt là saigon-lu). Không làm trực tiếp trên nhánh này. Mọi thay đổi B/C/D/E phải qua nhánh tích hợp và kiểm tra bên dưới trước khi B/E cùng chấp thuận merge vào nhánh đích.

**Điều kiện bắt đầu:** chỉ tạo nhánh công việc sau khi người dùng hoàn tất nội dung giao việc và đưa `docs/AGENTS.md`, `docs/endless_gameplay_and_ui_plan.md`, `docs/endless_gameplay_team_assignments.md` lên GitHub trong `feat/saigon-lu`. Các file local chưa commit không tự xuất hiện trong nhánh/clone của agent.

### Tên nhánh

- Nhánh tích hợp tạm: `integration/endless-gameplay` — B tạo, E review; là nơi ghép các nhánh và chạy kiểm tra liên thành phần.
- B: `feat/endless-ui-b`
- E: `feat/endless-card-camera-e`
- C: `feat/endless-core-c`
- D: `feat/endless-graph-flood-d`
- Nếu các nhánh trên đã tồn tại, tiếp tục dùng nhánh đó; không tạo biến thể tên khác nếu chưa thống nhất với nhóm.

### Người điều phối tích hợp

- **B là integrator chính:** tạo và giữ nhánh `integration/endless-gameplay`, theo dõi PR/merge, xử lý thứ tự tích hợp và test logic liên module.
- **E là co-integrator:** review các merge ảnh hưởng card/camera/UI, chạy kiểm tra giao diện và thay B điều phối khi cần.
- Chỉ merge `integration/endless-gameplay` vào `feat/saigon-lu` khi cả B và E xác nhận các cổng test ở dưới đã đạt. Thay đổi thiết kế/baseline ngoài phạm vi đã chốt vẫn cần hỏi người dùng.

### Tạo nhánh công việc

Mỗi người bắt đầu từ bản mới nhất của nhánh đích. Trước khi đổi nhánh, commit phần việc của mình hoặc xác nhận worktree sạch; không stash, xóa hay đưa file không thuộc task vào commit.

B tạo nhánh ghép một lần; E cùng theo dõi và review:

```sh
git fetch origin
git switch feat/saigon-lu
git pull --ff-only origin feat/saigon-lu
git switch -c integration/endless-gameplay
git push -u origin integration/endless-gameplay
```

Sau đó từng thành viên tạo nhánh riêng từ `feat/saigon-lu`:

```sh
git fetch origin
git switch feat/saigon-lu
git pull --ff-only origin feat/saigon-lu
git switch -c <branch-name>
git push -u origin <branch-name>
```

Thay `<branch-name>` bằng đúng tên nhánh được phân công ở trên. Nếu nhánh công việc đã tồn tại, dùng `git switch <branch-name>` thay cho `git switch -c`, rồi lấy cập nhật từ nhánh tích hợp theo flow dưới đây. Không force-push nhánh dùng chung và không reset/ghi đè thay đổi người khác.

### Thứ tự merge giữa các nhánh và handoff

Không merge nhánh của nhau qua lại theo vòng tròn. Dùng `integration/endless-gameplay` làm điểm ghép chung; mỗi người đưa nhánh của mình vào đó, rồi người phụ thuộc merge bản tích hợp mới nhất vào nhánh riêng để kiểm tra tương tác:

1. **B tạo, E review** nhánh `integration/endless-gameplay` từ `feat/saigon-lu`, push lên remote và thông báo cho nhóm.
2. **C** hoàn thành API/state card, inventory và endless trên `feat/endless-core-c`; chạy test phần mình, sau đó merge/PR nhánh C vào `integration/endless-gameplay`.
3. **D** lấy cập nhật integration vào `feat/endless-graph-flood-d` (bao gồm C), xử lý conflict cùng owner file, chạy test flood/graph/placement và xác nhận contract C↔D; sau đó merge/PR D trở lại integration.
4. **E** lấy integration mới nhất (C+D) vào `feat/endless-card-camera-e`; nối card UI/camera, chạy test UI và chọn reward; sau đó merge/PR E trở lại integration.
5. **B** lấy integration mới nhất (C+D+E) vào `feat/endless-ui-b`; nối HUD/toolbar/placement input, kiểm tra tương tác UI với inventory và graph; sau đó merge/PR B trở lại integration.
6. Sau mỗi lần merge, B chạy test liên quan trên integration; E review thay đổi UI và cùng xác nhận lỗi đã được sửa. Owner module sửa trên nhánh riêng, chạy lại test, merge bản sửa vào integration; các nhánh phụ thuộc phải lấy integration mới nhất và chạy lại test liên quan.
7. Khi integration xanh và hoàn tất playtest, B và E cùng chấp thuận rồi merge `integration/endless-gameplay` vào `feat/saigon-lu`. Không merge trực tiếp các nhánh cá nhân vào saigon-lu.

Để lấy nhánh tích hợp về nhánh cá nhân sau khi đã commit phần đang làm:

```sh
git fetch origin
git switch <branch-name>
git merge origin/integration/endless-gameplay
```

Thay tên nhánh bằng nhánh được phân công. Giải quyết conflict bằng cách giữ đúng ownership/API trong mục 2; nếu hai thay đổi cùng sửa file shared hoặc không rõ hành vi mong muốn, dừng và trao đổi với owner thay vì tự chọn/ghi đè.

### Cổng kiểm tra trước mỗi lần merge

- Người gửi PR ghi rõ mục tiêu, file/API thay đổi, test đã chạy, cách tái hiện thủ công và lỗi còn biết; chỉ stage file thuộc task.
- Chạy test nhỏ nhất bao phủ phần sửa. Sau khi merge nhánh phụ thuộc, chạy lại test trên phần đã ghép; không coi test riêng từng nhánh là đủ cho tích hợp.
- Tối thiểu trên integration: chạy test card/wave/inventory, flood/boat/graph placement/refund; mở game và kiểm tra draft → chọn card → bắt đầu wave → đặt/xóa item → wave 3 sang endless; kiểm tra ít nhất một kích thước viewport phụ.
- B/E xác nhận UI/input bằng chạy game; C/D xác nhận logic bằng test. Nếu bất kỳ cổng nào lỗi, không merge integration vào saigon-lu cho tới khi sửa và chạy lại.
- Mỗi PR nên tập trung một milestone. Không merge đồng thời các thay đổi chạm cùng file shared; C/D có thể dùng AI hỗ trợ nhưng phải đọc diff, xác nhận hành vi và chịu trách nhiệm về test.

## 10. Bảng theo dõi

### B — UI gameplay

- [ ] Chốt layout/style cùng E.
- [ ] HUD, toolbar hover và inventory count.
- [ ] Chế độ Vẽ/Xóa cạnh phải.
- [ ] Clock controls, nút góc trên trái, cảnh báo và failure pips.
- [ ] Visual QA ở 16:10 và các trạng thái gameplay.
- [ ] PR có hướng dẫn test tương tác.

### E — Card UI và camera

- [ ] Card draft panel nối API C.
- [ ] Bốn card, bundle reward, chọn duy nhất một card.
- [ ] Gỡ shop UI cũ và nối luồng chọn card qua `reward_popup.gd/.tscn`.
- [ ] Viewport 1920×1200, map 16:9 giữa nền.
- [ ] Zoom theo con trỏ; min zoom thấy full map.
- [ ] QA card/game freeze và camera ở nhiều kích cỡ viewport.

### C — Endless/card backend

- [ ] Wave generator hỗ trợ index sau wave 3.
- [ ] Mốc sống sót ba wave và win/loss theo tiến trình.
- [ ] Card generator bốn lựa chọn khác nhau và reward model.
- [ ] Inventory grant/reset; bỏ mua bằng quỹ.
- [ ] Test state transition, duplicate selection, reward và restart.

### D — Flood/graph/movement

- [ ] D1 flood depth gradient và boat navigation mask.
- [ ] Kiểm tra số liệu dry/shallow/deep và routeability trên map.
- [ ] D2 API/placement cho traffic light, roundabout, highway và Ferry.
- [ ] Test graph, placement/refund và tuyến highway.
- [ ] D3 gia tốc/phanh theo phương tiện và test dừng/đổi cạnh.

### Ma trận test theo owner

Chạy các scene tự động gần nhất với phần sửa. Từ thư mục project, dùng Godot console 4.7.2 theo mẫu:

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/<test_name>_auto.tscn
```

| Owner | Test tự động tối thiểu | Kiểm tra thủ công bắt buộc |
|---|---|---|
| **B** | `test_game_auto.tscn` | HUD/toolbar hover, Draw/Erase, pause/tốc độ, cảnh báo, 1920×1200 và một viewport khác. |
| **E** | `test_game_auto.tscn`, `test_graph_view_auto.tscn` | Draft trước wave 1/giữa wave, chọn đúng một card, game đứng yên khi draft, zoom theo con trỏ, map không méo ở 1920×1200 và viewport khác. |
| **C** | `test_game_auto.tscn`, `test_balance_auto.tscn` | Draft/reset, grant reward đúng một lần, profile wave 4/6/8/18 và amount scale card, chạy qua wave 3 tới endless và thua trước/sau milestone. |
| **D** | `test_flood_auto.tscn`, `test_boat_auto.tscn`, `test_traffic_auto.tscn`, `test_road_auto.tscn`, `test_ferry_auto.tscn` | Vị trí flood/depth mask, pathfinding, item invalid/valid, consume/refund đúng một lần, traffic light không tự xuất hiện. |
| **Integration (B/E)** | `test_game_auto.tscn`, `test_graph_view_auto.tscn` và các test module C/D phía trên | Chạy game end-to-end qua draft → wave → đặt/xóa item → wave 3 → endless; UI/input và viewport. |

Nếu một scene test liên quan bị đổi tên/xóa, owner cập nhật bảng này cùng PR. Test tự động không thay cho kiểm tra thủ công các thao tác UI/camera.

## 11. Tài liệu/source liên quan

- [Hướng dẫn agent hiện tại](./AGENTS.md)
- [Kế hoạch Endless, vật phẩm và UI gameplay](./endless_gameplay_and_ui_plan.md)
- [Tài liệu Xe dân và nâng cấp xe cứu hộ — tham khảo format/phân rã task](../FEATURE_XE_DAN_VA_NANG_CAP_XE_CUU_HO.md)
- [Config và luật cân bằng](../autoload/config.gd)
- [GameManager và vòng đời ván](../autoload/game_manager.gd)
- [GraphManager](../graph/graph_manager.gd)
- [FloodManager](../flood/flood_manager.gd)
- [RescueManager](../rescue/rescue_manager.gd)
- [HUD hiện tại](../ui/hud.gd), [toolbar](../ui/tool_bar.gd), [UI coordinator](../ui/ui_root.gd)
- [Stage/camera hiện tại](../game/stage_view.gd)
- [Test tự động](../tests)
