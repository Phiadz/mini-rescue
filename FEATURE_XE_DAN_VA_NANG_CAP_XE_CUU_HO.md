# FEATURE SPEC: XE DÂN CÁ NHÂN & NÂNG CẤP XE CỨU HỘ

**Dự án:** Floodline (Cứu hộ 0 giờ) | **Nhánh chính:** `feat/saigon-lu`  
**Ngày cập nhật:** 19/11/2026  
**Người phê duyệt / Phụ trách chính:** Lộc (Lead)  
**Trạng thái:** ✅ Đã hoàn thiện thiết kế & Khảo sát mã nguồn — SẴN SÀNG BÀN GIAO (B, C, D)

---

## I. TỔNG QUAN Ý TƯỞNG

### 1. Vấn đề hiện tại
- Với 12 xe tải + 8 ca-nô chạy từ 2 kho cố định, mật độ phương tiện trên đường quá thưa thớt.
- Cơ chế kẹt xe (Anti-bunching / Giảm tốc khi bám đuôi và nhường đường tại ngã ba, ngã tư) không phát huy được rõ nét vì đường phố gần như trống trải.
- Một chiếc xe cứu hộ chạy băng băng khắp bản đồ chỉ để giao một món hàng chưa thể hiện được sự quá tải thực tế khi đô thị ngập lụt.

### 2. Giải pháp cốt lõi
- **Xe dân cá nhân (Cơ chế sinh xe kiểu Mini Motorways):** Mỗi ngôi nhà / điểm dân cư (District / House) khi có SOS mà đường bộ còn đi được (DRY hoặc SHALLOW) sẽ **tự động sinh ra 1 xe cá nhân (Xe máy hoặc Ô tô con)** chạy ra Kho nhận hàng cứu trợ rồi tự chở về nhà.
- **Tạo ùn tắc tự nhiên:** Khi nhiều nhà cùng phát SOS, hàng chục xe máy và ô tô của dân sẽ đổ ra đường cùng lúc, tạo nên cảnh tượng ùn ứ, kẹt xe chân thực tại các nút giao và cổng kho trung tâm.
- **Tái định vị Xe tải & Ca-nô:** Trở thành **"Đội Cứu hộ Hạng nặng"**. Xe tải và ca-nô chỉ xuất kích khi khu vực bị ngập sâu/cô lập mà xe dân không thể tự đi được, hoặc khi xe của dân gặp sự cố giữa đường.
- **Nâng cấp trọng tải (Multi-carry):** Xe tải và ca-nô có thể nâng cấp trong Cửa hàng để chở cùng lúc 2 phần hàng, đi cứu trợ liên hoàn nhiều nhà ngập trong 1 chuyến.

---

## II. CƠ CHẾ CHI TIẾT

### A. Xe Dân Cá Nhân (Civilian Vehicle)

#### A1. Phân loại xe
Mỗi nhà dân / điểm dân cư (`NodeKind.DISTRICT`) khi khởi tạo sẽ được gán ngẫu nhiên 1 loại xe cá nhân theo tỉ lệ:

| Loại xe | Tỉ lệ | Tốc độ | Kích thước hiển thị | Khả năng lội nước | Asset Icon (ĐÃ CÓ SẴN) |
|:---|:---:|:---:|:---|:---|:---|
| **Xe máy** | **70%** | **220 px/s** (nhanh) | `Vector2(14, 9)` px (chiếm 1/2 làn, 2 xe ngược chiều lách được) | Đi tốt đường khô (DRY), lội chậm qua ngập nông (SHALLOW), **không đi được ngập sâu (DEEP)** | `assets/icons/motorbike.svg` |
| **Ô tô con** | **30%** | **160 px/s** (vừa) | `Vector2(18, 11)` px (chiếm trọn 1 làn, dễ ùn ứ) | Đi tốt đường khô (DRY), **không đi được ngập nông (SHALLOW) và ngập sâu (DEEP)** | `assets/icons/car.svg` |

> *Ghi chú:* Cả 2 file SVG đã có sẵn trong dự án với chuẩn góc nhìn từ trên xuống (top-down), đầu xe quay sang phải (hướng $0^\circ$). Người B **không cần thiết kế lại icon**.

#### A2. Điều kiện kích hoạt & Vòng đời SOS
Khi một nhà phát tín hiệu SOS:
1. Hệ thống tìm đường (Dijkstra) từ nhà đến Kho (HUB) gần nhất theo khả năng di chuyển của xe nhà đó:
   - Nếu là **Xe máy**: Tìm đường qua các cạnh DRY và SHALLOW.
   - Nếu là **Ô tô con**: Chỉ tìm đường qua các cạnh DRY hoàn toàn.
2. **Trường hợp có đường:** Xe dân xuất phát từ nhà → chạy đến Kho → nhận 1 đơn vị hàng cứu trợ → quay về nhà.
   - ⚠️ **Quy tắc quan trọng:** SOS của nhà chỉ được tính là hoàn thành (`RESCUED`) khi **xe của dân đã về tới tận nhà**.
3. **Trường hợp không có đường (nhà bị ngập cô lập):**
   - Xe dân không thể xuất phát.
   - SOS lập tức được chuyển sang hàng chờ của Đội Cứu hộ Hạng nặng (Xe tải hoặc Ca-nô).

#### A3. Hệ số tốc độ theo trạng thái đường (SPEED_FACTOR)

| Loại xe (VehicleType) | DRY (0) | SHALLOW (1) | DEEP (2) | Ghi chú |
|:---|:---:|:---:|:---:|:---|
| `TRUCK` (0) | 1.0 | 0.5 | 0.0 | Xe tải gầm cao lội được ngập vừa |
| `BOAT` (1) | 0.0 | 0.5 | 1.0 | Ca-nô đi nước ngập vừa và sâu |
| `MOTORBIKE` (2) | **1.0** | **0.4** | **0.0** | Xe máy lội chậm qua ngập nông, cấm đi ngập sâu |
| `CAR` (3) | **1.0** | **0.0** | **0.0** | Ô tô gầm thấp chỉ đi đường khô ráo |

#### A4. Xử lý khi nước dâng giữa đường (Cơ chế Biến mất & Bàn giao SOS)
> **Quyết định chốt từ Lộc (Lead):** Để tránh game bị rối và khó kiểm soát (do hiện tại game chưa có cơ chế phân luồng, điều tiết giao thông phức tạp cho xe dân), chúng ta **KHÔNG** để xe bị kẹt lại tạo thêm SOS phụ hay đứng chặn đường.

- **Khi xe dân đang chạy giữa đường mà đoạn đường phía trước hoặc ngay dưới chân bị ngập** (Xe máy gặp DEEP, hoặc Ô tô gặp SHALLOW/DEEP):
  1. Xe dân **lập tức biến mất (despawn)** kèm hiệu ứng mờ dần nhẹ (Fade-out trong 0.25s).
  2. Không để lại vật cản trên đường (tránh làm tê liệt toàn bộ luồng xe phía sau).
  3. **Yêu cầu cứu trợ (SOS) của ngôi nhà đó được chuyển ngay lập tức vào hàng chờ của Xe tải / Ca-nô cứu hộ.**
  4. Xe tải hoặc Ca-nô sẽ nhận lệnh mang hàng đến thẳng nhà dân đó để hoàn thành cứu trợ.

#### A5. Trạng thái hoạt động của Xe Dân (State Flow)
```
[PARKED tại nhà]
     │
     │ (Nhà có SOS + Tìm được đường hợp lệ tới Kho)
     ▼
[EN_ROUTE → HUB]  ─────── (Đường bị ngập giữa chừng) ───────► [BIẾN MẤT]
     │                                                            │
     │ (Đến cổng Kho)                                            │ (Bàn giao SOS)
     ▼                                                            ▼
[LOADING tại HUB] (Dừng 0.3s nhận hàng từ Kho)          [Đội Cứu hộ hạng nặng]
     │                                                  (Xe tải / Ca-nô xuất phát)
     ▼
[EN_ROUTE → HOME] ─────── (Đường về bị ngập) ──────────────► [BIẾN MẤT]
     │
     │ (Về đến nhà an toàn)
     ▼
[RESCUED] (Tích điểm, trừ SOS) ──► Xe quay về trạng thái [PARKED]
```

---

### B. Nâng cấp Xe Cứu Hộ (Multi-carry Capacity)

#### B1. Trọng tải xe
- **Mặc định đầu ván game:**
  - Xe tải chở: **1 hàng**
  - Ca-nô chở: **1 hàng**
- **Sau khi nâng cấp tại Cửa hàng (Shop):**
  - Xe tải nâng cấp: chở được **2 hàng**
  - Ca-nô nâng cấp: chở được **2 hàng**
  - *(Ghi chú tương lai: có thể mở rộng lên 3 hàng ở các phiên bản sau nếu cần).*

#### B2. Lộ trình giao hàng tuần tự (Multi-drop Routing)
Khi xe tải hoặc ca-nô có sức chứa $\ge 2$ và có nhiều hơn 1 nhà ngập đang cần cứu trợ:
```
KHO (Nhận 2 hàng) ──► [Nhà A: Giao 1 hàng] ──► [Nhà B: Giao 1 hàng] ──► VỀ KHO
```
- **Thuật toán gom cụm (Clustering):**
  - Tìm các nhà có SOS gần nhau (trong bán kính $\le 3$ ô lưới $\approx 120\text{px}$).
  - Ưu tiên nhà có thời gian đếm ngược SOS sắp hết trước.
- **Xử lý ngoại lệ:** Nếu Nhà A bị hỏng/timeout (SOS Failed) khi xe đang trên đường tới, xe tự động bỏ qua và chuyển hướng sang Nhà B.

#### B3. Nâng cấp trong Cửa hàng Cứu trợ (Shop Reward)
Bổ sung 2 thẻ nâng cấp vào hệ thống Reward:

| Tên hiển thị | Khóa (Enum) | Giá (Quỹ) | Tác dụng | Giới hạn |
|:---|:---:|:---:|:---|:---:|
| 🚚 **XE TẢI 2 NGĂN** | `UPGRADE_TRUCK_CAP` (3) | 150 | Tăng sức chở toàn bộ xe tải lên 2 | Mua 1 lần duy nhất / ván |
| ⛵ **CA-NÔ 2 NGĂN** | `UPGRADE_BOAT_CAP` (4) | 120 | Tăng sức chở toàn bộ ca-nô lên 2 | Mua 1 lần duy nhất / ván |

---

## III. TỔNG QUAN TÁC ĐỘNG TỚI CODE HIỆN TẠI (ĐÃ KHẢO SÁT KỸ)

| File | Hành động | Nội dung chính cần làm |
|:---|:---:|:---|
| `autoload/types.gd` | Sửa | Thêm `MOTORBIKE = 2`, `CAR = 3` vào `VehicleType`; thêm `UPGRADE_TRUCK_CAP = 3`, `UPGRADE_BOAT_CAP = 4` vào `Reward`. |
| `autoload/config.gd` | Sửa | Thêm `MOTORBIKE_SPEED := 220.0`, `CAR_SPEED := 160.0`; cập nhật `SPEED_FACTOR`; thêm giá vào `SHOP_PRICES`; **cập nhật hàm `base_speed()`** cho cả 4 loại xe. |
| `autoload/event_bus.gd` | Sửa | Thêm signal `truck_capacity_upgraded(new_cap)`, `boat_capacity_upgraded(new_cap)`. |
| `graph/edge.gd` | Sửa | `speed_factor()`: đảm bảo cạnh sông `boat_only` chặn mọi xe đường bộ (`if boat_only and vehicle_type != Types.VehicleType.BOAT: return 0.0`). |
| `graph/graph_manager.gd` | Sửa nhỏ | `find_path()` hỗ trợ tìm đường cho `MOTORBIKE` và `CAR` theo đúng mức ngập. |
| `rescue/rescue_manager.gd` | Sửa lớn | Quản lý class `CivilianVehicle` (kế thừa `Vehicle`); phân luồng `_dispatch()`; xử lý despawn khi ngập; gom chuyến multi-drop cho xe cứu hộ. |
| `autoload/game_manager.gd` | Sửa | Quản lý biến `truck_capacity` và `boat_capacity`, xử lý mua thưởng trong `choose_reward()`. |
| `ui/reward_popup.gd` | Sửa | Thêm 2 thẻ nâng cấp; điều chỉnh layout hiển thị để không tràn màn hình; disable nút khi đã mua. |
| `assets/icons/motorbike.svg` | **Đã có sẵn** | Icon xe máy có sẵn trong project. |
| `assets/icons/car.svg` | **Đã có sẵn** | Icon ô tô con có sẵn trong project. |

---

## IV. ĐỀ XUẤT CÂN BẰNG & MẬT ĐỘ XE DÂN (TRAFFIC JAM)

> **Giải đáp thắc mắc của Lộc về Giới hạn xe dân:**

1. **Khuyến nghị:** **KHÔNG cần đặt giới hạn cứng (hard limit) ngay từ đầu**.
2. **Lý do thực tế từ logic game:**
   - Mỗi ngôi nhà chỉ có duy nhất **1 xe**.
   - Xe chỉ chạy khi nhà đó **đang có SOS** VÀ **đường tới Kho không bị ngập sâu**.
   - Cơ chế sinh SOS trong game diễn ra tuần tự theo từng khoảng thời gian (`sos_interval` từ 3.8s đến 7.0s tùy Wave).
   - Với quy mô bản đồ hiện tại (khoảng 30 - 45 ngôi nhà), số lượng xe dân lưu thông trên đường ở giờ cao điểm tự nhiên chỉ rơi vào khoảng **8 – 15 xe**.
   - Khi cộng thêm 12 xe tải + 8 ca-nô, tổng số phương tiện trên đường sẽ đạt khoảng **25 – 35 xe**. Mật độ này là **con số vàng**: vừa đủ để tạo ùn tắc mắt thấy rõ ràng ở các ngã tư trung tâm và cổng Kho, nhưng không làm sập FPS hay nghẽn chết hoàn toàn mạng lưới giao thông.
3. **Quy trình cân bằng:** Người C hoàn thiện logic trước, sau đó dùng bot test tự động (`test_balance_auto`) chạy kiểm tra qua 5 wave để quan sát; nếu có hiện tượng kẹt cứng không thể giải tỏa mới cân nhắc đặt trần tối đa.

---

## V. PHÂN CÔNG NHIỆM VỤ CHI TIẾT (B, C, D)

```
        ┌──────────────────────────────────────────────────────────┐
        │  Thứ tự triển khai & Merge nhánh:                        │
        │  NGƯỜI C (Backend Core)  ──► Merge trước vào feat/saigon-lu  │
        │  NGƯỜI D (UI Shop)       ──► Merge tiếp theo             │
        │  NGƯỜI B (Visual & Icon) ──► Merge sau cùng              │
        └──────────────────────────────────────────────────────────┘
```

---

### 🧑‍💻 NGƯỜI C — Data Model & Điều phối Logic (Backend Core)
*Nhánh làm việc:* `feat/civilian-vehicle`  
*Phụ trách:* Toàn bộ logic sinh xe, đường đi của xe dân, cơ chế despawn khi ngập, gom chuyến xe cứu trợ.

#### 💡 Gợi ý kiến trúc quan trọng cho Người C:
> Trong `rescue_manager.gd`, hệ thống kẹt xe (`congestion_factor`, `_grid`, `_nearby`, nhường đường ngã ba/ngã tư, vòng xoay, đèn đỏ) đều dựa vào việc các phương tiện được đăng ký trong `_grid` như một đối tượng `Vehicle`.  
> 👉 **Do đó:** Lớp `CivilianVehicle` nên **kế thừa trực tiếp `Vehicle`** (hoặc mở rộng `Vehicle` với thuộc tính `is_civilian: bool = true`, `home_node_id: int`). Nhờ vậy, xe dân và xe cứu hộ sẽ **tự động tương tác, nhường đường và gây kẹt xe lẫn nhau ngay lập tức** mà không cần viết lại thuật toán giao thông!

#### Checklist công việc:
- [ ] **`autoload/types.gd`:**
  - Thêm `MOTORBIKE = 2`, `CAR = 3` vào `enum VehicleType`.
  - Thêm `UPGRADE_TRUCK_CAP = 3`, `UPGRADE_BOAT_CAP = 4` vào `enum Reward`.
- [ ] **`autoload/config.gd`:**
  - Thêm tốc độ: `MOTORBIKE_SPEED := 220.0`, `CAR_SPEED := 160.0`.
  - Thêm thời gian bốc hàng: `CIVILIAN_LOAD_TIME := 0.3`.
  - Cập nhật ma trận `SPEED_FACTOR` cho cả 4 loại phương tiện (`TRUCK`, `BOAT`, `MOTORBIKE`, `CAR`).
  - Thêm giá Shop: `SHOP_PRICES[3] = 150`, `SHOP_PRICES[4] = 120`.
  - **Sửa hàm `base_speed(vehicle_type: int) -> float`** bằng câu lệnh `match` hỗ trợ đủ 4 loại phương tiện.
- [ ] **`graph/edge.gd`:**
  - Sửa `speed_factor()`: `if boat_only and vehicle_type != Types.VehicleType.BOAT: return 0.0`.
- [ ] **`graph/graph_manager.gd`:**
  - Cập nhật `find_path()` chấp nhận `VehicleType.MOTORBIKE` (chỉ đi qua DRY và SHALLOW) và `VehicleType.CAR` (chỉ đi qua DRY).
- [ ] **`rescue/rescue_manager.gd`:**
  - Khởi tạo xe cá nhân cho **tất cả** các node dân cư `NodeKind.DISTRICT` (bao gồm các điểm quận mở đầu ván `id: 2..16` và các nhà mọc thêm `id: 100+` khi bắt tín hiệu `point_added`):
    - Tỉ lệ ngẫu nhiên: 70% xe máy, 30% ô tô con.
  - Sửa hàm `_dispatch()`:
    - Khi có SOS tại nhà: kiểm tra xe của nhà đó trước. Nếu có đường đi tới Kho → kích hoạt xe dân xuất phát.
    - Nếu không có đường (nhà bị ngập cô lập) → đưa vào hàng chờ xe tải/ca-nô.
  - Xử lý xe gặp ngập giữa đường:
    - Kiểm tra mặt đường mỗi frame hoặc mỗi node di chuyển: nếu mặt đường ngập vượt quá khả năng chịu đựng của xe → kích hoạt **biến mất (despawn)**.
    - Chuyển tiếp SOS của nhà đó sang hàng chờ xe tải/ca-nô tiếp tục giải cứu.
  - Logic xe về đến nhà:
    - Khi xe về đến nhà an toàn: phát `EventBus.sos_rescued`, xe chuyển về `PARKED`.
  - Logic gom chuyến (Multi-drop) cho Xe tải / Ca-nô:
    - Khi `GameManager.truck_capacity >= 2` (hoặc boat), hỗ trợ gom 2 SOS gần nhau vào 1 hành trình tuần tự.
- [ ] **Kiểm tra (Testing):**
  - Viết/chạy script test logic đảm bảo xe dân tự đi lấy hàng, biến mất khi gặp ngập, và SOS không bị mất.

---

### 🎨 NGƯỜI B — Hiển thị Phương tiện & Hiệu ứng (Visual)
*Nhánh làm việc:* `feat/civilian-visual`  
*Phụ trách:* Render xe máy, ô tô con trên bản đồ, góc xoay và hiệu ứng mờ dần khi gặp nước ngập.

#### 💡 Lưu ý quan trọng cho Người B:
> Asset icon xe máy và ô tô con **ĐÃ CÓ SẴN** tại:
> - `assets/icons/motorbike.svg`
> - `assets/icons/car.svg`  
> Người B **KHÔNG CẦN VẼ LẠI ASSET**. Chỉ tập trung vào phần hiển thị và hiệu ứng trong mã nguồn!

#### Checklist công việc:
- [ ] **Nạp Asset Icon:**
  - Nạp sẵn `preload("res://assets/icons/motorbike.svg")` và `preload("res://assets/icons/car.svg")`.
- [ ] **Hiển thị xe trong game (`_draw()`):**
  - Kích thước vẽ (Draw Scale):
    - Xe máy: `Vector2(14, 9)` px (nhỏ gọn, tạo cảm giác lách làn).
    - Ô tô con: `Vector2(18, 11)` px (vừa vặn 1 làn đường).
  - Trạng thái hiển thị:
    - `PARKED`: Xe ẩn hoàn toàn (đang đỗ trong nhà).
    - `EN_ROUTE`: Xe hiện hình, đầu xe tự xoay theo hướng di chuyển (`heading.angle()`) và lật hình khi chạy sang trái (`left := heading.x < 0.0`) như xe tải.
    - Khi bị ngập: Kích hoạt hiệu ứng Tween mờ dần (`modulate.a` từ 1.0 về 0.0 trong 0.25s) trước khi `queue_free()` hoặc ẩn đi.
- [ ] **Lưu ý:**
  - **Không** thêm bộ đếm số lượng xe dân lên thanh HUD (tránh làm rối mắt giao diện).

---

### 🏪 NGƯỜI D — Giao diện Cửa hàng Cứu trợ (UI Shop & State)
*Nhánh làm việc:* `feat/shop-upgrade`  
*Phụ trách:* Hiển thị thẻ nâng cấp tải trọng trong Shop, xử lý bố cục giao diện và kích hoạt trạng thái nâng cấp vào game.

#### 💡 Lưu ý quan trọng về Layout cho Người D:
> Cửa sổ Cửa hàng hiện tại (`reward_popup.gd`) có chiều cao cố định **652px** với 3 thẻ xếp dọc ở vị trí `y = 200 + i * 123`.  
> ⚠️ **Nếu xếp dọc 5 thẻ:** Vị trí thẻ thứ 5 sẽ tới $200 + 4 \times 123 = 692\text{px}$, vượt ra ngoài cửa sổ và đè lên nút "XONG" ở $y = 592\text{px}$!  
> 👉 **Giải pháp đề xuất cho Người D:**
> 1. **Cách 1 (Khuyên dùng):** Thu gọn chiều cao mỗi thẻ từ 110px xuống còn **~70px**, khoảng cách 10px để 5 thẻ vừa khít chiều cao.
> 2. **Cách 2:** Chia làm 2 cột (Cột trái: 3 thẻ vật tư/xe thêm; Cột phải: 2 thẻ nâng cấp tải trọng).
> 3. **Cách 3:** Đặt danh sách thẻ vào một `ScrollContainer` có chiều cao khoảng 380px.

#### Checklist công việc:
- [ ] **`autoload/game_manager.gd`:**
  - Khai báo biến toàn cục:
    ```gdscript
    var truck_capacity: int = 1
    var boat_capacity: int = 1
    ```
  - Cập nhật hàm xử lý phần thưởng:
    - Khi chọn `Reward.UPGRADE_TRUCK_CAP`: `truck_capacity = 2`.
    - Khi chọn `Reward.UPGRADE_BOAT_CAP`: `boat_capacity = 2`.
  - Đảm bảo reset cả 2 biến về 1 khi bắt đầu ván chơi mới (`restart_game()`).
- [ ] **`autoload/event_bus.gd`:**
  - Khai báo signal:
    ```gdscript
    signal truck_capacity_upgraded(new_capacity: int)
    signal boat_capacity_upgraded(new_capacity: int)
    ```
- [ ] **`ui/reward_popup.gd`:**
  - Bố trí lại layout giao diện (theo 1 trong các cách ở trên).
  - Bổ sung 2 thẻ mua nâng cấp:
    - Thẻ 1: 🚚 **XE TẢI 2 NGĂN** — "Mỗi xe tải chở được 2 kiện hàng cứu trợ cùng lúc." — Giá: 150 Quỹ.
    - Thẻ 2: ⛵ **CA-NÔ 2 NGĂN** — "Mỗi ca-nô chở được 2 kiện hàng cứu trợ cùng lúc." — Giá: 120 Quỹ.
  - Cơ chế mua duy nhất: Sau khi người chơi đã mua, nút bấm chuyển sang trạng thái Disabled và hiển thị nhãn `[✓ ĐÃ SỞ HỮU]`.
- [ ] **Kiểm tra (Testing):**
  - Mua thử thẻ trong Shop: quỹ bị trừ đúng giá, thẻ bị vô hiệu hóa không cho mua lần 2.
  - Giá trị `truck_capacity` / `boat_capacity` cập nhật đúng trong `GameManager`.

---

## VI. QUY TRÌNH LÀM VIỆC & THEO DÕI TIẾN ĐỘ (WORKFLOW)

### 1. Nguyên tắc làm việc chung
1. **Phân nhánh độc lập:** Mỗi người làm trên nhánh riêng của mình (`feat/civilian-vehicle`, `feat/civilian-visual`, `feat/shop-upgrade`).
2. **Hỏi Lead ngay khi vướng:** *"Nếu có bất kỳ điểm nào chưa rõ về logic hoặc gặp lỗi xung đột, hãy hỏi ngay Lộc (Lead). Tuyệt đối không tự ý sửa đổi quy tắc trong spec."*
3. **Thứ tự tích hợp (Merge):**
   - Người C tạo PR vào `feat/saigon-lu` đầu tiên và kiểm tra chạy thông suốt.
   - Người D kéo code mới nhất từ `feat/saigon-lu` về nhánh mình, tích hợp phần Shop và merge tiếp theo.
   - Người B cập nhật hiệu ứng hiển thị cuối cùng.

---

### 2. Bảng Theo Dõi Tiến Độ Cá Nhân (Nhật ký công việc)

> *Mỗi thành viên cập nhật nhật ký của mình vào bảng dưới đây trước khi báo cáo cho Lộc.*

#### 📋 Tiến độ NGƯỜI C (Backend Core)
- [ ] Thiết lập Enum & Config (`types.gd`, `config.gd`, `base_speed()`)
- [ ] Cập nhật chặn xe đường bộ trên cạnh `boat_only` (`edge.gd`)
- [ ] Tìm đường cho Xe máy & Ô tô (`graph_manager.gd`)
- [ ] Khởi tạo xe cá nhân cho toàn bộ nhà dân (`rescue_manager.gd`)
- [ ] Phân luồng điều phối xe dân xuất phát lấy hàng
- [ ] Cơ chế xe dân biến mất khi gặp ngập & bàn giao SOS cho xe cứu hộ
- [ ] Thuật toán gom cụm Multi-drop cho xe tải/ca-nô chở 2 hàng
- [ ] Kiểm thử tự động (Unit Test / Bot Test)

*Ghi chú của C:*
> `[C - Ngày ...]` Đã làm: ... | Vướng mắc: ... | Cần hỏi Lộc: ...

---

#### 📋 Tiến độ NGƯỜI D (UI Shop & State)
- [x] Khai báo biến `truck_capacity`, `boat_capacity` trong `GameManager`
- [x] Bổ sung tín hiệu thông báo nâng cấp trong `EventBus`
- [x] Thiết kế & Tinh chỉnh layout 5 thẻ trong `reward_popup.gd`
- [x] Khóa thẻ khi đã mua (chỉ mua 1 lần)
- [ ] Kiểm thử trừ Quỹ và hiệu lực nâng cấp trong ván chơi *(đã xác nhận Quỹ bị trừ khi mua. Chờ người C tích hợp Multi-drop để kiểm tra xe tải và ca-nô có giao được 2 kiện cho 2 nhà trong cùng một chuyến)*.
*Ghi chú của D:*
> `[D - Ngày 20/11/2026]` Đã làm: Bố trí Shop 5 thẻ, gồm Xe tải 2 ngăn (150 Quỹ) và Ca-nô 2 ngăn (120 Quỹ). Khi mua thành công, `GameManager` trừ Quỹ, tăng sức chứa tương ứng từ 1 lên 2 và phát tín hiệu nâng cấp. Thẻ đã mua hiện `✓ ĐÃ SỞ HỮU` và chỉ mua được một lần mỗi ván. Khi bắt đầu ván mới, sức chứa của cả hai loại xe trở về 1. | Vướng mắc: `RescueManager` hiện chưa dùng hai biến sức chứa để giao 2 kiện trong một chuyến. | Cần hỏi Lộc: Không có câu hỏi.

---

#### 📋 Tiến độ NGƯỜI B (Visual & Hiển thị)
- [ ] Nạp asset SVG có sẵn (`assets/icons/motorbike.svg`, `car.svg`)
- [ ] Cài đặt kích thước hiển thị `(14×9)` và `(18×11)` px
- [ ] Xoay đầu xe theo hướng chạy & lật hình khi sang trái
- [ ] Hiệu ứng ẩn xe khi đỗ trong nhà và mờ dần khi gặp ngập biến mất
- [ ] Kiểm tra thẩm mỹ tổng thể trên bản đồ mùa lũ

*Ghi chú của B:*
> `[B - Ngày ...]` Đã làm: ... | Vướng mắc: ... | Cần hỏi Lộc: ...

---

## VII. THÔNG SỐ CÂN BẰNG THAM KHẢO

| Tham số | Giá trị | Giải thích |
|:---|:---:|:---|
| `MOTORBIKE_SPEED` | 220 px/s | Nhanh hơn xe tải (180 px/s) để luồn lách nhanh |
| `CAR_SPEED` | 160 px/s | Chậm hơn một chút, dễ gây ùn tắc nhẹ |
| `CIVILIAN_LOAD_TIME` | 0.3s | Dân nhận hàng nhanh hơn xe cứu hộ (0.5s) |
| `TRUCK_CAPACITY_DEFAULT` | 1 kiện | Ban đầu |
| `BOAT_CAPACITY_DEFAULT` | 1 kiện | Ban đầu |
| `UPGRADE_TRUCK_CAP_PRICE` | 150 Quỹ | Cân đối trong Shop |
| `UPGRADE_BOAT_CAP_PRICE` | 120 Quỹ | Cân đối trong Shop |

---
*Tài liệu này là chuẩn mực thiết kế chính thức của tính năng Xe Dân & Nâng Cấp Cứu Hộ. Mọi thắc mắc và đóng góp vui lòng trao đổi trực tiếp với Lộc.*
