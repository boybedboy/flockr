# Flockr

แชทกลุ่มทัวร์ที่มีแผนที่สด รัศมีแจ้งเตือนแยกตามกลุ่มอายุ และ Tag Card (NFC/BLE)

```
flockr/
├─ docker-compose.yml   PostGIS + server
├─ server/              Node.js API + WebSocket
└─ app/                 Flutter (Android / iOS)
```

## Server

```powershell
docker compose up -d db          # PostGIS บนพอร์ต 5433
cd server
npm install
npm start                        # http://localhost:3100 (รัน migration ให้เองตอนเปิด)
npm test                         # ทดสอบการคำนวณรัศมี
node scripts/smoke.js            # ทดสอบทั้งระบบกับ server ที่รันอยู่
```

รันทั้งหมดใน Docker: `docker compose up -d --build` (ต้องตั้ง `JWT_SECRET` เมื่อใช้งานจริง)

### กลุ่มการดูแล (`server/src/geo.js`)

| key | กลุ่ม | รัศมี (สัดส่วนของรัศมีผู้ใหญ่) | สัญญาณหายเมื่อเงียบเกิน |
|---|---|---|---|
| toddler | เด็กเล็ก 0–5 | 20% | 90 วินาที |
| child | เด็กโต 6–12 | 40% | 5 นาที |
| teen | วัยรุ่น 13–17 | 80% | 5 นาที |
| adult | ผู้ใหญ่ 18–59 | 100% | 5 นาที |
| senior | ผู้สูงวัย 60+ | 50% | 5 นาที |
| special | ดูแลพิเศษ | 20% | 60 วินาที |

ถ้ามีคนออกนอกรัศมี ระบบจะนับว่า "กลับเข้าพื้นที่" ก็ต่อเมื่อเขาเดินกลับเข้ามาลึกกว่าขอบรัศมี 10% เพื่อไม่ให้แจ้งเตือนสลับไปมาตอนยืนอยู่ตรงขอบ

### API หลัก

| Method | Path | ใคร | ใช้ทำอะไร |
|---|---|---|---|
| POST | /api/auth/signup, /api/auth/login | ไกด์ | สร้างบัญชี / เข้าสู่ระบบ |
| POST/GET/PATCH | /api/trips[/:id] | ไกด์ | สร้างทริป ดูทริป ตั้งรัศมี |
| POST | /api/trips/:id/guide-position | ไกด์ | ตำแหน่งไกด์ (จุดศูนย์กลาง) |
| POST | /api/join | ลูกทัวร์ | เข้าร่วมด้วยรหัส 6 ตัว (ต้องยินยอม PDPA) |
| POST | /api/trips/:id/members | ไกด์ | เพิ่มคนที่ใช้การ์ดแทนมือถือ |
| POST | /api/me/position, /api/me/sos | ลูกทัวร์ | ส่งตำแหน่ง / ขอความช่วยเหลือ |
| GET/POST | /api/trips/:id/messages | ทุกคนในทริป | แชท |
| POST | /api/cards/batch | admin | สร้างรหัสการ์ดล่วงหน้าสำหรับโรงพิมพ์ |
| POST | /api/cards/:code/chip | ไกด์ | บันทึก UID ของชิปหลังเขียนการ์ด |
| POST | /api/cards/bind, /api/cards/scan | ไกด์ | ผูกการ์ดกับคน / สแกนเช็กชื่อ |
| POST | /api/sightings | Hub / มือถือไกด์ | รายงานว่าเห็นการ์ด BLE ใบไหนบ้าง |
| GET/POST | /api/public/cards/:code[/found] | คนทั่วไป | สแกน QR เมื่อพบคนหลง |
| WS | /ws?token=…&trip=… | ทุกคนในทริป | รับเหตุการณ์ message, position, alert, member, checkin, trip แบบเรียลไทม์ |

## App (Flutter)

เครื่องนี้ยังไม่ได้ติดตั้ง Flutter โค้ดใน `app/lib` จึงยังไม่เคยถูกคอมไพล์ ขั้นตอนแรก:

```powershell
cd app
flutter create --org app.flockr --platforms android,ios .   # สร้างโฟลเดอร์ android/ios โดยไม่ทับ lib/
flutter pub get
flutter run --dart-define=API=http://10.0.2.2:3100          # Android emulator
```

ต้องเพิ่มสิทธิ์เองหลังรัน `flutter create`:

- **Android** `android/app/src/main/AndroidManifest.xml`:
  `ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `NFC`, `INTERNET`, `FOREGROUND_SERVICE_LOCATION`
- **iOS** `ios/Runner/Info.plist`:
  `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, `NFCReaderUsageDescription`
  และเปิด capability **Near Field Communication Tag Reading** ใน Xcode

## ยังไม่ได้ทำ

- ส่งตำแหน่งตอนแอปอยู่เบื้องหลัง (foreground service บน Android / background mode บน iOS)
- Push notification (FCM) เมื่อแอปปิดอยู่
- สแกน BLE ในแอปไกด์ เพื่อส่งไปที่ `/api/sightings`
- เว็บหลังบ้านสำหรับบริษัท (สร้างทริป, ผลิตการ์ด, บิล) และระบบชำระเงิน
- งานลบตำแหน่งอัตโนมัติ 30 วันหลังจบทริป (PDPA)
- เฟิร์มแวร์ Hub (ESP32)
