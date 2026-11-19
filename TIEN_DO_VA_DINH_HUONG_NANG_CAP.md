# BÁO CÁO TIẾN ĐỘ & HƯỚNG DẪN HOÀN THIỆN CÁC TÍNH NĂNG MỚI (OVERHAUL ROADMAP)
**Dự án:** Floodline (Cứu hộ 0 giờ) | **Nhánh kiểm tra:** `feat/saigon-lu` (`current branch/mini-rescue`)  
**Ngày cập nhật:** 17/11/2026  
**Cập nhật lần 2 (E, 17/11/2026):** đã gộp `feat/ket-xe` vào `feat/saigon-lu` (merge `4406cf7`). Feature B và C đã xong, đã tích ở mục IV; chỗ nào làm khác hướng dẫn có ghi chú "→". Feature D (phao) chưa làm.

---

## I. TỔNG QUAN TIẾN ĐỘ THỰC TẾ

Đối chiếu giữa **Mục tiêu Nâng cấp Gameplay** và **Mã nguồn thực tế trên nhánh `feat/saigon-lu`**:

| STT | Tính năng / Module | Tiến độ | Tình trạng mã nguồn thực tế |
| :---: | :--- | :---: | :--- |
| **01** | **Khung kiến trúc (SVG, No TileMap, Grid 32×18)** | **100%** | **Rất tốt:** Giữ nguyên nền vector phẳng `saigon_mm_base.svg`, dữ liệu lưới 32×18 (`CELL_SIZE = 40px`), vẽ đường bằng CanvasItem `_draw()`. |
| **02** | **Feature A: Cellular Automata River Flooding** | **100%** | **ĐÃ HOÀN TẤT XUẤT SẮC:** Lũ lan 4 hướng từ ô sông/biển, phân biệt mặt cầu và lòng sông, hiển thị bằng Shader đường đồng mức `water.gdshader`. |
| **03** | **Cửa hàng Cứu trợ (Shop System) & Tua nhanh** | **100%** | **ĐÃ LÀM XONG:** Đã có cơ chế mua ô đường, thêm xe bằng tiền Quỹ cứu trợ (đơn vị 10 triệu VNĐ) giữa các đợt lũ, nút tua nhanh x1/x2/x3. |
| **04** | **Feature C: Lightweight Traffic Congestion** | **100%** | **ĐÃ LÀM XONG (E, `c714dea`):** Bám đuôi cùng làn (dưới 34 px chạy 50%, dưới 20 px dừng), nhường đường ở ngã ba/ngã tư, chờ quá 3 giây thì đi chậm qua, tìm đường né cạnh đông xe, đèn phanh khi kẹt. Không dùng node vật lý: tìm xe ở gần bằng lưới ô 40 px. |
| **05** | **Feature B: Wave-based Expansion & Zoom** | **100%** | **ĐÃ LÀM XONG (E, `944704e`), theo hướng khác:** dùng chính map Sài Gòn chia 3 vùng thay vì vẽ map to hơn. Camera phóng to rồi thu ra dần (zoom 1,8 → 1,35 → 1), mở 8 → 12 → 15 khu. Ngoài vùng chơi không tô đường, không sinh SOS. |
| **06** | **Feature D: Multi-Modal Logistics (Hệ thống Phao)** | **20%** | **CHƯA CÓ PHAO:** Mới chỉ có giải pháp tình thế cho Ca-nô đi trên đường khô ở 25% tốc độ (`SPEED_FACTOR = 0.25`). Chưa có logic trung chuyển hàng Xe tải ↔ Ca-nô qua sông. |

---

## II. ĐÁNH GIÁ CHI TIẾT NHỮNG GÌ ĐÃ HOÀN THÀNH TỐT

1. **Lũ lan theo ô (Cellular Automata) & Shader Nước (Rất xuất sắc):**
   - Đã bổ sung mảng `grid.water` vào `map_saigon.json` để xác định chính xác các ô lòng sông.
   - Hàm `_spread(dt)` trong `flood_manager.gd` mô phỏng nước tràn từ sông/biển sang các ô lân cận theo độ cao rất mượt mà.
   - Sáng tạo cơ chế **mặt cầu (`_deck`) và lòng sông (`_ground`)**: Đường người chơi vẽ qua sông đóng vai trò là Cầu, chỉ ngập khi mực nước vượt mặt cầu, không cản trở dòng lũ chảy bên dưới.
   - Shader `water.gdshader` kết hợp `saigon_height.png` tạo hiệu ứng viền nước bám sát đường đồng mức tự nhiên, giữ trọn vẹn chất nghệ thuật của Mini Motorways.

2. **Cơ chế Kinh tế & Cửa hàng cứu trợ:**
   - Thay thế việc chọn ngẫu nhiên 1 trong 3 thẻ bài bằng **Cửa hàng cứu trợ**: Người chơi tích lũy điểm cứu trợ thành Quỹ tiền tệ (10 triệu VNĐ/đơn vị) để chủ động mua ô đường, xe tải hoặc ca-nô.
   - Hỗ trợ nút tua nhanh x1, x2, x3 giúp trải nghiệm chơi mượt và giảm thời gian chờ đợi.

3. **Kẹt xe thuần logic (E, `c714dea`):**
   - `RescueManager.congestion_factor(v)` trả hệ số tốc độ (0 / 0,5 / 1) mỗi khung hình; `Vehicle.advance` nhân tốc độ với hệ số này.
   - Bám đuôi: xe phía trước cùng hướng, cùng làn, cách dưới `FOLLOW_GAP` 34 px thì chạy 50%, dưới `STOP_GAP` 20 px thì dừng.
   - Ngã ba, ngã tư (node có từ 3 cạnh): xe sắp vào (trong 46 px) nhường xe đang ở trong nút, hoặc xe từ nhánh cắt ngang ở gần nút hơn. Nếu bằng nhau thì xe mã nhỏ đi trước, nên hai xe không bao giờ cùng nhường nhau. Chờ quá `JAM_GIVE_UP` 3 giây thì đi chậm qua.
   - Tìm đường né chỗ đông: `GraphManager.find_path(..., edge_penalty)` cộng 1,5 giây cho mỗi xe sắp đi qua một cạnh.
   - Tìm xe ở gần bằng lưới ô 40 px, mỗi xe chỉ so với xe ở các ô quanh nó, nên 200 xe vẫn nhẹ. Test: `tests/test_traffic_auto` (16 kiểm tra).

4. **Vùng chơi theo đợt & camera (E, `944704e`):**
   - `game/stage_view.gd`: Camera2D tạo bằng code (GameManager thêm vào World mỗi ván); các vùng lấy từ khóa `stages` trong `map_saigon.json`.
   - Đợt 1 zoom 1,8 (8 khu trung tâm và Kho Tân Sơn Nhất), đợt 2 zoom 1,35 (12 khu, thêm Kho Cát Lái), đợt 3 zoom 1 (cả 15 khu). Camera chuyển vùng bằng Tween 1,6 giây ở đầu lượt nghỉ; cửa hàng mở sau khi camera chuyển xong.
   - Ngoài vùng chơi: phủ lớp tối nhẹ, không tô đường, không sinh SOS (`GameManager.is_in_play`).

5. **Cân bằng lại thực tế theo góp ý của Lộc (đã cập nhật vào code sau merge):**
   - **Mỗi SOS chỉ cần 1 xe:** `sos_units = 1` trong tất cả các Wave (`autoload/config.gd`). Một xe tải/ca-nô chở đủ hàng cho một nhà, không còn cảnh 8–10 xe bu vào một căn nhà.
   - **Quy mô xe ban đầu hợp lý:** Đầu ván chỉ có **20 xe** gồm **12 xe tải** và **8 ca-nô** (`START_TRUCKS = 12`, `START_BOATS = 8` trong `rescue_manager.gd`), chia đều cho các kho.
   - **Thưởng xe ở Cửa hàng cứu trợ:** Mua xe được `+2 xe` mỗi lần (`REWARD_VEHICLE_BONUS = 2`), không cộng dồn ồ ạt +10 xe.
   - **Bãi đỗ xe chuẩn Mini Motorways:** Mỗi kho có bãi đỗ 6 chỗ, bến ca-nô cầu tàu 4 chỗ; xe ra vào có thứ tự, không chồng lên nhau.
   - **Thời hạn SOS điều chỉnh tương ứng:** Đợt 1: 40s/30s, Đợt 2: 38s/29s, Đợt 3: 30s/23s để đảm bảo nhịp độ căng thẳng vừa phải mà không gây quá tải giao thông vô lý.

---

## III. HƯỚNG DẪN CHI TIẾT CÁC TÍNH NĂNG CÒN THIẾU CẦN BỔ SUNG

### 1. FEATURE D: HỆ THỐNG PHAO TRUNG CHUYỂN & CA-NÔ VƯỢT SÔNG (ƯU TIÊN SỐ 1)
> **Hiện trạng:** Nhóm đang dùng giải pháp tạm: `SPEED_FACTOR[BOAT][DRY] = 0.25` (Ca-nô đi trên đường bộ bằng rơ-moóc).  
> **Mục tiêu thiết kế:** Xây dựng hệ thống vận chuyển đa phương thức (Intermodal Transport) đậm chất cứu hộ lũ lụt Việt Nam.

#### A. Vấn đề cốt lõi về Đồ thị (Graph):
- Sông không có đường nối sẵn giữa 2 bờ, do đó thuật toán Dijkstra sẽ báo `found = false` nếu điểm SOS nằm bên kia sông.
- **Giải pháp:** Khi người chơi cắm Phao A ở bờ bên này và Phao B ở bờ bên kia:
  - `GraphManager` tự động sinh ra một **Cạnh nước ảo (Virtual Water Edge)** nối giữa Node Phao A và Node Phao B.
  - Cạnh này có thuộc tính: `speed_factor(BOAT) = 1.0` (Ca-nô đi bình thường), `speed_factor(TRUCK) = 0.0` (Xe tải tuyệt đối không đi được).

#### B. Quy trình Điều phối đa chặng (Multi-leg Dispatching):
1. **Chặng 1:** Xe tải lấy hàng từ Kho (`HUB`) $\to$ chở đến Phao A $\to$ dỡ hàng thành kiện hàng chờ tại bến Phao A.
2. **Chặng 2:** Ca-nô nhận lệnh $\to$ bơi đến Phao A bốc kiện hàng $\to$ vượt sông qua Cạnh nước ảo $\to$ thả kiện hàng tại Phao B.
3. **Chặng 3:** Xe tải ở bờ bên kia $\to$ chạy tới Phao B bốc hàng $\to$ chở thẳng đến điểm dân cư SOS hoàn tất cứu trợ.
*(Lưu ý: Nếu điểm SOS nằm ngay trong vùng ngập sâu, Ca-nô có thể bốc hàng từ Phao A bơi thẳng tới giao trực tiếp cho dân).*

#### C. Cơ chế Phao tự động thụt lùi (Auto-fallback):
- Khi nước lũ dâng làm ô đường mép nước chuyển sang trạng thái `DEEP` (xe tải không đi được nữa), Phao đặt tại ô đó sẽ bị cô lập.
- **Thuật toán xử lý:** Khi phát hiện ô đặt Phao bị ngập `DEEP`:
  - Phao tự động dò ngược theo chuỗi ô đường (`segment`) kết nối với nó để tìm ô gần nhất còn ở trạng thái `DRY` hoặc `SHALLOW`.
  - Tự động di dời vị trí Phao về ô cạn đó. Người chơi không bị ức chế phải nhặt và cắm lại phao thủ công khi triều cường dâng.
- Cho phép người chơi click chuột phải để thu hồi Phao về kho và cắm lại chỗ khác bất cứ lúc nào.

---

### 2. FEATURE C: CƠ CHẾ KẸT XE THUẦN TOÁN HỌC (LIGHTWEIGHT TRAFFIC) (ƯU TIÊN SỐ 2)
> **ĐÃ LÀM (E, `c714dea`), xem mục II.3.** Khác hướng dẫn ở hai chỗ: (1) không lọc theo `edge_id`, vì trên đường ô mỗi ô là một cạnh nên xe đổi cạnh liên tục; thay vào đó xét xe cùng hướng, cùng làn qua lưới ô; (2) ở nút giao, xe dừng hẳn để nhường theo thứ tự ai gần hơn đi trước (không giảm còn 30%), chờ quá 3 giây thì đi chậm qua.

> **Yêu cầu nghiêm ngặt:** **TUYỆT ĐỐI KHÔNG DÙNG** các node vật lý của Godot (`Area2D`, `RayCast2D`, `CharacterBody2D`, `RigidBody2D`) vì sẽ gây nặng máy và xung đột logic với Graph.

#### A. Bám đuôi cùng làn (Tailgating):
- Trong hàm `Vehicle.advance(delta)`:
  - Duyệt danh sách các xe đang chạy trên cùng `edge_id` và cùng hướng di chuyển.
  - Nếu khoảng cách giữa xe sau và xe trước nhỏ hơn ngưỡng an toàn (ví dụ: `distance < 28px`):
    - Tốc độ của xe sau tự động giảm xuống bằng tốc độ xe trước, hoặc giảm còn `50%` tốc độ tối đa (`speed *= 0.5`).
    - Khi xe trước tăng tốc hoặc rẽ hướng khác, xe sau tự động tăng tốc trở lại.

#### B. Giảm tốc tại nút giao (Intersections):
- Một nút giao được định nghĩa là `MapNode` có từ 3 cạnh nối trở lên (`_adj[node_id].size() >= 3`).
- Khi xe chuẩn bị đi vào nút giao (cách tâm nút `< 20px`), kiểm tra xem có xe khác đang nằm trong phạm vi nút giao hay không:
  - Nếu có: Xe đến sau phải giảm tốc độ còn `30%` (hoặc dừng chờ `0.5s`) để nhường đường.
  - Điều này lập tức tạo ra bài toán phân luồng giao thông giống Mini Motorways: người chơi sẽ phải vẽ thêm các tuyến đường vòng, đường tránh để không bị tắc nghẽn ở ngã tư trung tâm.

---

### 3. FEATURE B: CAMERA ZOOM & MỞ RỘNG BẢN ĐỒ THEO WAVE (ƯU TIÊN SỐ 3)
> **ĐÃ LÀM (E, `944704e`), xem mục II.4.** Khác hướng dẫn: không zoom out ra ngoài bản đồ (1,0 → 0,85 → 0,70) mà phóng to vào trung tâm rồi thu ra dần (1,8 → 1,35 → 1). Zoom luôn ≥ 1 nên không cần vẽ nền SVG to hơn, không lộ viền đen, và chữ, biểu tượng không bao giờ nhỏ hơn kích thước gốc.

> **Mục tiêu:** Tạo cảm giác quy mô thành phố và vùng lũ mở rộng dần theo thời gian.

#### A. Cấu trúc Camera:
- Thêm node `Camera2D` vào `main.tscn` (làm con của `Main` hoặc `World`).
- Đặt `position` tại tâm bản đồ `Vector2(640, 360)`.
- Mặc định ở Wave 1: `zoom = Vector2(1.0, 1.0)`.

#### B. Nhịp mở rộng theo Wave:
- **Khi bắt đầu Wave mới:**
  - Dùng `Tween` nội suy `Camera2D.zoom` từ `1.0` $\to$ `0.85` (Wave 2) $\to$ `0.70` (Wave 3) trong vòng 2 giây mượt mà.
  - Kích hoạt thêm các điểm dân cư mới ở vùng rìa ngoài (ví dụ: Nhà Bè, Cần Giờ, Hóc Môn...). Các wave đầu chỉ kích hoạt các điểm trung tâm (Calmette, Hàng Xanh, Bệnh viện Gia Định).
- **Xử lý viền màn hình:** Vì ảnh nền SVG hiện tại có kích thước 1280×720:
  - Cần vẽ ảnh nền SVG rộng hơn (ví dụ 1920×1080 hoặc 2560×1440), hoặc đặt màu nền ngoài canvas trùng với mã màu đất `#f4f0e7` để khi zoom out không bị viền đen.

#### C. Cơ chế Giữ kích thước Icon cảnh báo (Clamped UI Scale):
- Các vật thể thế giới (nhà, đường, xe, sông) sẽ tự động thu nhỏ lại khi camera zoom out (đúng nguyên lý 2D).
- **RIÊNG CÁC ICON CẢNH BÁO SOS:**
  - Vòng tròn đếm ngược SOS (`sos_marker.gd`) cần nhân với hệ số tỉ lệ nghịch với zoom camera: `scale = Vector2.ONE / camera.zoom.x`.
  - Nhờ đó, dù camera có zoom ra xa đến đâu thì đồng hồ đếm ngược và chấm than nguy cấp vẫn giữ nguyên kích thước rõ ràng trên màn hình, giúp người chơi không bị sót nhà sắp chết.

---

## IV. DANH SÁCH CÁC ĐẦU VIỆC CẦN LÀM (TODO CHECKLIST)

Các đầu việc được xếp theo thứ tự ưu tiên triển khai để nhóm tự phân công:

- [ ] **1. Hệ thống Phao & Đồ thị Đa phương thức (Multi-Modal):**
  - [ ] Thiết kế icon Phao trung chuyển (`buoy.svg`).
  - [ ] Viết cơ chế đặt/thu hồi Phao tại mép nước trong `GraphManager`.
  - [ ] Viết hàm tạo Cạnh nước ảo (`add_virtual_water_edge(buoy_a, buoy_b)`) chỉ cho Ca-nô đi qua.
  - [ ] Cập nhật thuật toán tìm đường Dijkstra hỗ trợ chia chặng: Đường bộ $\to$ Bến Phao $\to$ Đường thủy $\to$ Đường bộ.
  - [ ] Cập nhật logic điều phối `RescueManager._dispatch()` cho quy trình dỡ/bốc hàng tại Phao.
  - [ ] Viết thuật toán Auto-fallback: Phao tự động lùi về ô cạn gần nhất khi ô hiện tại bị ngập `DEEP`.

- [x] **2. Cơ chế Kẹt xe thuần Logic (Traffic Congestion):** (E, `c714dea`)
  - [x] Thêm logic kiểm tra bám đuôi (tailgating) trên cùng `edge_id` trong `Vehicle.advance()` để giảm 50% tốc độ xe sau. → Xét xe cùng hướng, cùng làn qua lưới ô 40 px thay vì `edge_id`; dưới 34 px chạy 50%, dưới 20 px dừng.
  - [x] Thêm logic giảm 30% tốc độ hoặc dừng nhường đường khi xe tiếp cận nút giao có xe khác đang rẽ. → Dừng nhường, xe gần nút hơn đi trước; chờ quá 3 giây thì đi chậm qua.
  - [x] (Thêm) Tìm đường né cạnh đông xe (`find_path` có `edge_penalty`); đèn phanh khi xe bị kẹt.

- [x] **3. Camera Zoom & Mở rộng Bản đồ (Wave Expansion):** (E, `944704e`)
  - [x] Thêm node `Camera2D` vào `main.tscn`. → Tạo bằng code trong `game/stage_view.gd`, không sửa `main.tscn`.
  - [x] Viết Tween nội suy `Camera2D.zoom` mượt mà khi bắt đầu Wave mới. → Phóng to rồi thu ra: zoom 1,8 → 1,35 → 1; Tween 1,6 giây ở đầu lượt nghỉ.
  - [x] Cập nhật logic sinh SOS: Wave 1 chỉ mở các điểm trung tâm, Wave 2 và 3 mới mở các điểm rìa ngoại ô. → Đợt 1: Calmette, Nguyễn Hữu Cảnh, BV Gia Định, Thảo Điền, Thanh Đa, Hàng Xanh, Mai Chí Thọ, Lê Đức Thọ; đợt 2 thêm Huỳnh Tấn Phát, Võ Nguyên Giáp, Đỗ Xuân Hợp, Trần Xuân Soạn và Kho Cát Lái; đợt 3 thêm Quốc lộ 50, Nhà Bè, Kinh Dương Vương.
  - [x] Mở rộng viền canvas hoặc kích thước ảnh nền SVG để tránh viền đen khi zoom out. → Không cần: zoom luôn ≥ 1, đợt cuối thấy đúng cả bản đồ 1280×720 nên không lộ viền.
  - [x] Gắn cơ chế Clamped Scale cho `sos_marker.gd` để icon SOS không bị bé li ti khi zoom xa. → Làm trong `ui/ui_root.gd`: bong bóng SOS có `scale = 1 / zoom`, giữ nguyên kích thước trên màn hình.
