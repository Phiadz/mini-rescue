# Kế hoạch phát triển: Endless, vật phẩm và UI gameplay

**Trạng thái:** Định hướng và quyết định thiết kế được ghi nhận; chưa triển khai các feature trong tài liệu này.
**Căn cứ:** Source/config/test hiện tại cùng các quyết định đã thống nhất trong trao đổi.
**Tài liệu MVP:** Chỉ dùng tham khảo lịch sử/ý tưởng. Source, config và test hiện tại mới là căn cứ xác nhận hành vi của phiên bản đang phát triển.

## 1. Mục tiêu

1. Thay shop bằng card draft chọn một trong bốn lựa chọn trước mỗi wave.
2. Biến đèn giao thông, roundabout, đường cao tốc và Ferry thành vật phẩm có inventory và thao tác đặt.
3. Chuyển ván chơi thành endless sau khi người chơi sống sót qua ba wave đầu.
4. Giữ lũ có tác động chiến thuật nhưng không để nước/ca-nô thay thế hoàn toàn bài toán giao thông.
5. Thêm gia tốc và phanh khác nhau theo loại phương tiện.
6. Thêm zoom camera thủ công và chuyển viewport sang 16:10.
7. Làm lại UI trong trận theo hướng tối giản, tối màu, ưu tiên biểu tượng và trạng thái trực quan.

Ảnh Mini Motorways chỉ tham khảo các nguyên tắc UI như toolbar gọn, điều khiển dễ nhận biết và số lượng vật phẩm dễ xem. Không sao chép hoặc trích xuất asset, source code hay thiết kế chi tiết độc quyền.

## 2. Hiện trạng đã xác nhận trong source

### Ván chơi, wave và map

- `autoload/config.gd` hiện khai báo ba wave, với mực nước đỉnh lần lượt khoảng 25, 55 và 90; game có thời lượng wave và thời gian nghỉ cố định.
- `autoload/game_manager.gd` kết thúc bằng chiến thắng sau wave cuối. Shop chỉ xuất hiện trong khoảng nghỉ; chưa có draft trước wave đầu.
- `flood/flood_manager.gd` chỉ bắt đầu wave nếu index nằm trong `Config.WAVES`. `rescue/rescue_manager.gd` đọc trực tiếp cấu hình wave khi sinh SOS/nhà nên không thể tăng index vô hạn như hiện tại.
- Lũ được mô phỏng theo từng ô và địa hình: nước lan từ biển/sông qua các ô kề, rồi độ sâu của ô quyết định trạng thái đường.
- `data/map_saigon.json` khai báo ba stage; stage cuối đã hiển thị toàn map 1280×720. Map hiện có lưới 32×18, không tự mở rộng sau stage cuối.

### Shop, điểm và phương tiện

- Shop hiện có lựa chọn thêm đường, thêm xe tải/ca-nô và nâng sức chứa.
- SOS cứu thành công tăng điểm và quỹ; mua đồ trong shop trừ quỹ. Một số giá tăng theo số lần mua.
- Xe hiện di chuyển theo tốc độ cơ sở nhân với hệ số loại đường và tắc nghẽn; `Vehicle.advance()` chưa duy trì tốc độ/gia tốc riêng cho từng xe.
- Hệ số đường hiện tại cho xe tải là nhanh trên đường khô, chậm hơn trên đường ngập vừa và không đi được trên đường ngập sâu. Ca-nô không đi trên đất khô, chậm ở vùng ngập vừa và đi được trên vùng ngập sâu.

### Hạ tầng, graph và UI

- Ferry là vật phẩm đặt tuyến qua sông; mặc định có một token. Có API tăng token nhưng chưa nối vào shop/card.
- Đèn giao thông hiện tự xuất hiện tại nút có ít nhất bốn nhánh; graph cho xe luân phiên quyền đi theo hai trục.
- Roundabout hiện tự nhận diện từ vòng đường khép kín 2×2 hoặc 3×3 và áp dụng luồng một chiều. Toolbar có icon/số lượng nhưng chưa hỗ trợ thao tác đặt đèn hoặc roundabout.
- Đường cao tốc chưa có vật phẩm, graph hay quy trình đặt tuyến.
- HUD hiện có điểm, wave, đếm ngược, mực nước, ngân sách đường, số SOS thất bại, tồn kho và banner. Toolbar chưa tự ẩn; xóa đường hiện bằng chuột phải kéo hoặc Delete.
- Nhiều kích thước/căn lề UI, scene và map đang dựa vào viewport 1280×720.

## 3. Thiết kế gameplay đã thống nhất

### 3.1 Card draft thay shop

- Bỏ cơ chế shop mua vật phẩm bằng quỹ; tiến trình nâng cấp dựa trên card.
- Trước wave đầu và giữa mỗi wave, dừng mô phỏng cho đến khi người chơi chọn một card.
- Mỗi lượt có bốn lựa chọn khác nhau; người chơi chọn đúng một. Card có thể là gói gồm nhiều phần thưởng và nhận toàn bộ gói khi được chọn.
- Card được tạo ngẫu nhiên theo run/wave và có trọng số tăng dần theo tiến trình. Không bảo đảm mỗi lượt có card thuộc một nhóm phần thưởng nhất định.
- Phần thưởng có thể gồm đường, xe tải/ca-nô, nâng sức chứa, đèn giao thông, roundabout, đường cao tốc và Ferry. Số lượng/chất lượng phần thưởng tăng dần theo wave nhưng cần giới hạn để cân bằng endless.
- Điểm hiển thị gọn, theo quy ước +1 cho mỗi SOS cứu thành công; điểm không còn là tiền để mua đồ trong shop.

### 3.2 Hạ tầng đặt được

- Đèn giao thông và roundabout là vật phẩm có số lượng; không tự nhận chỉ vì người chơi vẽ đủ hình học.
- Đèn được đặt ở junction có ít nhất ba nhánh. Nếu junction bị phá và đèn không còn hợp lệ, hoàn lại vật phẩm.
- Roundabout item tự tạo footprint vòng xoay tại junction được chọn và kết nối lại các nhánh đường phù hợp.
- Một vòng đường người chơi tự vẽ nhưng không đặt roundabout vẫn là đường/giao lộ thường; nó không tự nhận luật chạy một chiều của roundabout. Giao lộ thường làm xe giảm tốc/nhường; roundabout được đặt giúp luồng xe đi qua thông suốt hơn.
- Một token highway tạo một tuyến. Người chơi chọn điểm đầu trên đường, xem tuyến cong preview rồi chọn điểm cuối trên đường. Tuyến đi trên cao, băng qua nhà/đường mà không tạo junction mặt đất; cả xe cứu hộ và xe dân thuộc nhóm phương tiện đường bộ đều sử dụng được. Xóa tuyến hoàn lại token.
- Ferry tiếp tục là vật phẩm đặt tuyến qua sông và có thể nhận qua card.

### 3.3 Endless, thất bại và map

- Sống sót qua ba wave đầu là mốc mở endless, không phải kết thúc ván.
- Thua trước khi qua mốc ba wave vẫn hiện kết quả thua.
- Sau mốc ba wave, chơi tiếp không giới hạn. Khi cuối cùng thua, dùng màn hình kết quả chiến thắng hiện tại, gồm khảo sát và chơi lại; người chơi được tính là đã hoàn thành thử thách sau mốc.
- Giai đoạn đầu giữ nguyên map hiện tại. Wave 3 đã hiển thị toàn map, nên endless không mặc định mở rộng map.
- Sau wave 3, không thể chỉ tiếp tục tăng mực nước vô hạn: cần tăng áp lực SOS/thời hạn, lượng nhiệm vụ đồng thời, traffic và nhịp sinh nhà; giữ cơ chế lũ có chu kỳ và giới hạn độ phủ để map không biến thành toàn nước.
- SOS nên được sinh ở vị trí có đường đi hợp lệ bằng phương tiện hiện có, hoặc theo quy tắc gameplay rõ ràng để nhiệm vụ không thể tiếp cận không gây thua bất công.

### 3.4 Hướng thiết kế lũ và giao thông

**Mục tiêu:** lũ tiếp tục ảnh hưởng đường đi và mở ra giá trị cho ca-nô, nhưng không khiến ca-nô trở thành câu trả lời cho mọi SOS và làm mất vai trò của đường bộ.

- Tách ba khái niệm: ô đang ngập/độ sâu, trạng thái sử dụng được của đường, và khả năng ca-nô đi qua.
- Hướng đã chọn để prototype: khi lũ lớn, vùng gần sông có thể ngập sâu trong phạm vi ban đầu khoảng 3–4 ô; vùng sâu trong đất liền chủ yếu ngập vừa thay vì ngập sâu toàn bộ.
- Khoảng cách 3–4 ô là giả thuyết để thử nghiệm, không phải bán kính cứng áp dụng đồng đều. Địa hình, vùng trũng, đường nước và vật cản cần ảnh hưởng tới độ sâu; nên có vùng chuyển tiếp tự nhiên giữa sâu và vừa.
- Ca-nô đi trên sông và các hành lang nước được đánh dấu trong dữ liệu map. Một ô phố ngập sâu không tự động trở thành tuyến ca-nô.
- Đường ngập vừa tiếp tục làm xe tải đi chậm; đường ngập sâu có thể đóng với xe đường bộ. Cần duy trì một số hành lang đường bộ liên tục, dựa trên địa hình cao/đường cao tốc, để xe tải và xe dân vẫn có vai trò ở endgame.
- Kết hợp hành lang đường an toàn với chu kỳ nước dâng/rút; dùng prototype/playtest để cân bằng. Lũ sâu gần sông tạo vùng nguy hiểm, còn nước ngập vừa trong đất liền tạo ma sát giao thông thay vì xóa toàn bộ mạng đường.
- Ở endless, ưu tiên tăng áp lực cứu hộ và traffic; giữ vùng ngập sâu có giới hạn hoặc theo chu kỳ thay vì cứ tăng độ sâu trên toàn map.

### 3.5 Chuyển động xe

- Gia tốc/phanh áp dụng cho các nhóm phương tiện đang có trong game, với thông số riêng theo loại xe.
- Xe tăng tốc khi rời trạng thái dừng; giảm tốc khi tiến đến junction cần nhường/dừng, đích cứu hộ, bến phà hoặc hàng chờ.
- Tốc độ cần điều chỉnh theo tốc độ tối đa của xe, loại cạnh, độ ngập và tắc nghẽn.
- Tốc độ hiện tại phải được giữ qua các ô/cạnh liền mạch; không reset gia tốc ở mỗi ô đường gây chuyển động giật.
- Giá trị gia tốc, phanh, tốc độ vào cua và khoảng cách dừng cần được cân bằng bằng prototype.

### 3.6 Camera và khung hình

- Mục tiêu viewport 16:10 ở độ phân giải 1920×1200.
- Giữ map 16:9 hiện tại ở giữa, không kéo giãn; dùng nền phù hợp cho phần viewport dư và căn UI theo viewport mới.
- Thêm zoom thủ công bằng con lăn, zoom hướng về vị trí con trỏ. Zoom nhỏ nhất hiển thị toàn map.
- Chưa có yêu cầu pan; giới hạn zoom lớn nhất cần được chốt khi kiểm tra UI/map thực tế.

### 3.7 UI gameplay

- Redesign trong phạm vi HUD gameplay, toolbar, card draft, cảnh báo và điều khiển trong trận. Menu và màn hình kết quả giữ gần như hiện tại.
- Phong cách tối, gọn, icon-first; giảm câu chữ, banner và popup. Tạo hình mới phù hợp Floodline, không sao chép asset/chi tiết độc quyền từ game tham khảo.
- Toolbar vật phẩm ở giữa cạnh dưới chỉ hiện khi con trỏ ở vùng đó; rời vùng thì tự ẩn, nhưng tiếp tục hiện trong lúc đặt vật phẩm. Icon cho biết số lượng còn lại.
- Cạnh phải có lựa chọn Vẽ và Xóa. Xóa bằng click/kéo khi đang ở chế độ Xóa; có thể giữ chuột phải làm shortcut.
- Cụm đồng hồ mở điều khiển Pause/Play và tốc độ x1/x2/x3. Pause không mở modal lớn.
- Có mũi tên ở góc trên trái để mở lựa chọn Chơi lại/Menu.
- Bỏ bộ đếm wave và số SOS thất bại dạng số khỏi HUD. Giữ luật thất bại hiện tại, biểu thị bằng tối đa ba chấm/icon nhỏ.
- Điểm là +1 mỗi SOS cứu thành công. Bỏ thông tin quỹ/shop khỏi gameplay HUD khi cơ chế mua bị loại bỏ.
- Bỏ banner thông thường; cảnh báo quan trọng về lũ/SOS vẫn cần thể hiện ngắn gọn qua icon/hiệu ứng trên map hoặc HUD. Card draft là panel lựa chọn có chủ đích.

## 4. Hệ quả và rủi ro kỹ thuật

### Wave, card và trạng thái run

- Cần thay truy cập trực tiếp `Config.WAVES[_wave]` bằng hàm/cấu hình wave có thể xử lý index sau wave 3.
- Draft cần chạy trước wave đầu và giữa các wave; mô phỏng phải đóng băng trong lúc chọn.
- Cần thống nhất model inventory/reward, xác suất card, phần thưởng gói, và cách cộng tồn kho cho từng item.
- `ScoreSystem`, `GameManager`, UI draft và end screen đang gắn với quỹ/shop, số wave cố định và trạng thái thắng/thua hiện tại; cần cập nhật đồng bộ.

### Flood, boat graph và routeability

- Hiện FloodManager báo ô ngập sâu thành flood node; GraphManager nối node với vùng nước/đường/điểm lân cận để ca-nô đi được. Cơ chế này đang ghép “ngập sâu” với “điều hướng được bằng ca-nô”.
- Cần giới hạn vùng sâu theo địa hình/khoảng cách thủy văn và tách mask tuyến ca-nô được phép đi khỏi mask ô đang ngập.
- Hành lang nước cần dữ liệu map và quy tắc mở/đóng phù hợp với độ sâu. Cần cập nhật graph, route tìm đường, hiển thị lũ và cảnh báo để cùng dùng một trạng thái nhất quán.
- Khi giữ một số tuyến đường bộ ở endgame, cần xác định chúng đến từ địa hình cao, đường cao tốc/cầu hay cấu hình map; không để SOS hợp lệ nhưng không thể tiếp cận.
- Sinh SOS cần kiểm tra routeability theo phương tiện sẵn có, hoặc có quy tắc rõ ràng cho nhiệm vụ đặc biệt chỉ tiếp cận được bằng đường thủy.

### Graph và hạ tầng

- Thay auto-detection đèn/roundabout bằng dữ liệu item được đặt và inventory từ card.
- Roundabout cần biến đổi graph junction thành footprint/luồng vòng xoay mà vẫn giữ kết nối các nhánh hợp lệ. Vòng đường tự vẽ không còn tự kích hoạt luật roundabout.
- Đèn cần xác định trạng thái giao lộ, thứ tự/pha cho xe và hoàn inventory khi junction không còn hợp lệ.
- Highway cần biểu diễn tuyến riêng trong graph, giữ tách biệt với giao cắt mặt đất, tính đường đi nhanh, render đường cong và preview hợp lệ/không hợp lệ.
- Ferry, traffic light, roundabout và highway cần cùng tuân theo quy trình inventory: kiểm tra điều kiện đặt, trừ vật phẩm khi đặt thành công, hoàn vật phẩm khi quy tắc thiết kế cho phép.

### Chuyển động, UI và viewport

- Gia tốc thêm trạng thái tốc độ vào từng xe; cần phối hợp với đổi cạnh, dừng ở junction, congestion, Ferry queue, cứu hộ và quay về kho.
- Chuyển 16:10 cần căn lại UI/nền; không kéo giãn map. Zoom-out quá xa sẽ lộ nền ngoài map.
- Toolbar tự ẩn cần được khóa mở trong lúc chọn/đặt item và không cản thao tác bản đồ.
- Bỏ shop/quỹ phải dọn các nhãn và luồng UI liên quan, nhưng không làm mất feedback điểm và trạng thái thất bại.

## 5. Các chi tiết còn cần thiết kế/cân bằng

Các mục dưới đây chưa cản việc chốt hướng tổng thể, nhưng cần hoàn tất trước hoặc trong prototype:

1. **Card pool:** số lượng mỗi loại phần thưởng, trọng số theo wave, card trùng giữa các lượt, giới hạn inventory và công thức tăng sức mạnh sau wave 3.
2. **Lũ:** cách tính ảnh hưởng của khoảng cách thủy văn/địa hình, phạm vi sâu ban đầu 3–4 ô, số tuyến bộ còn lại và tần suất/độ dài chu kỳ rút nước.
3. **Hành lang ca-nô:** định dạng mask/dữ liệu map, vị trí các tuyến được đánh dấu và cách nối với bến/điểm SOS.
4. **Roundabout:** footprint cụ thể, số nhánh tối đa, quy tắc nối/xóa và việc hoàn item khi roundabout bị phá.
5. **Highway:** giới hạn chiều dài/tốc độ/số tuyến, cách chọn endpoint hợp lệ và xử lý khi một đầu đường bị xóa. Xóa tuyến hoàn lại token là quyết định đã chốt.
6. **Ferry và item khác:** quy tắc hoàn token khi tuyến/bố trí bị xóa, trừ trường hợp đã chốt riêng cho highway và đèn.
7. **Gia tốc/phanh:** thông số theo loại xe, tốc độ qua junction/turn, khoảng cách dừng và cách phối hợp với traffic light/roundabout.
8. **Endless:** giới hạn/mức tăng SOS, thời hạn, nhà, phương tiện giao thông và độ khó sau wave 3; tránh chỉ tăng số lượng đến mức map quá tải ngoài ý muốn.
9. **Camera/UI:** zoom tối đa, thiết kế nền 16:10, trạng thái của mũi tên góc trên trái và xác nhận cuối cùng trên build 1920×1200.

## 6. Tiêu chí prototype và kiểm thử

- Card draft hiện bốn lựa chọn khác nhau, chỉ nhận một lựa chọn, đóng băng thời gian khi chờ và cấp đúng inventory; không còn đường mua bằng quỹ.
- Đèn chỉ đặt được tại junction từ ba nhánh; roundabout chỉ có luật vòng xoay khi được đặt; xóa junction có đèn hoàn item theo thiết kế.
- Highway tạo một tuyến trên cao dùng được cho xe cứu hộ và xe dân đường bộ, không tạo junction tại chỗ giao cắt, và xóa tuyến hoàn token.
- Thử flood trên map hiện tại ở nhiều wave: vùng gần sông có thể sâu hơn; vùng sâu trong đất liền chủ yếu vừa; vẫn có một số tuyến đường bộ liên tục.
- Thử pathfinding ca-nô: ô phố ngập sâu ngoài mask tuyến không tự đi được; các tuyến ca-nô đã đánh dấu mở/đóng đúng theo trạng thái nước.
- SOS được tạo ở vị trí có route hợp lệ hoặc có chỉ báo/quy tắc công bằng cho nhiệm vụ đặc biệt; không tạo nhiệm vụ bất khả thi ngẫu nhiên.
- Qua ba wave đầu không kết thúc ván; wave tiếp tục chạy sau đó mà không truy cập vượt mảng. Thua trước mốc là thua; thua sau mốc hiện end screen chiến thắng hiện tại.
- Kiểm tra tốc độ xe tăng từ trạng thái dừng, phanh trước điểm dừng và liền mạch qua nhiều ô cùng đoạn.
- 16:10 hiển thị map 16:9 không méo, zoom nhỏ nhất vừa map, zoom theo con trỏ; toolbar/HUD không tràn ở 1920×1200.
- Xác nhận UI trong trận không còn banner/quỹ/wave/failure count dạng số không cần thiết; cảnh báo và ba chấm thất bại vẫn dễ hiểu.

## 7. Workstream có thể chia cho nhóm

1. **Flood và map:** mô hình độ sâu theo địa hình/khoảng cách thủy văn, vùng sâu/vừa, chu kỳ nước và thử nghiệm trên map hiện tại.
2. **Boat navigation và graph:** mask tuyến ca-nô, kết nối bến, trạng thái tuyến theo độ sâu và test pathfinding.
3. **Hạ tầng đặt được:** inventory/tool placement cho đèn, roundabout, highway và Ferry; graph/render/preview; refund rules.
4. **Endless, SOS và vehicle motion:** sinh wave sau wave 3, nhịp SOS/nhà/deadline, routeable spawn, gia tốc/phanh và congestion.
5. **Card draft và progression:** thay shop, tạo bốn lựa chọn, trọng số/phần thưởng, đóng băng run và cấp inventory.
6. **Camera/UI:** viewport 16:10, nền, zoom theo con trỏ, HUD tối giản, toolbar hover, xóa đường và clock controls.
7. **Tích hợp/playtest:** kiểm tra các hệ thống kết hợp, cân bằng độ khó và cập nhật test hồi quy.

Các phần phụ thuộc lẫn nhau: item placement cần inventory; boat graph cần flood/nav rules; SOS scaling cần routeability; UI draft cần reward model. Nên thống nhất các interface/state chung trước khi nhiều workstream triển khai song song.

## 8. Source chính để tiếp tục

- [Config và luật cân bằng](../autoload/config.gd)
- [GameManager và vòng đời ván](../autoload/game_manager.gd)
- [GraphManager](../graph/graph_manager.gd)
- [FloodManager](../flood/flood_manager.gd)
- [RescueManager](../rescue/rescue_manager.gd)
- [HUD hiện tại](../ui/hud.gd), [toolbar](../ui/tool_bar.gd), [UI coordinator](../ui/ui_root.gd)
- [Stage/camera hiện tại](../game/stage_view.gd)
- [Test tự động](../tests)
