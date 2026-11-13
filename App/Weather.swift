// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import Foundation

/// WEATHER: the weather where the phone is, from Open-Meteo (open-meteo.com: free for apps with no ads and no subscriptions, its
/// name shown with the data). Asked every 15 minutes (its current values are 15-minute ones), sooner when the phone has moved
/// 5 km, the location rounded to 2 decimals (about 1 km) before it leaves the phone. Its values in Sender.space's order, and the
/// sky in words for /weather/text. On the queue it is given.
final class Weather {
    var got: ([Float], String) -> Void = { _, _ in }   // on the queue
    var said: (String) -> Void = { _ in }              // why there is none (each reason once), for the console
    private let queue: DispatchQueue
    private var at = -1e9, la = 999.0, lo = 999.0, asking = false, told = ""

    init(queue: DispatchQueue) { self.queue = queue }

    /// Where the phone is now (degrees): Open-Meteo is asked when it is time. On the queue
    func near(_ lat: Double, _ lon: Double, _ now: Double) {
        let moved = hypot(lat - la, (lon - lo) * cos(lat * .pi / 180)) * 111 > 5   // km
        guard !asking, now - at >= 900 || (moved && now - at >= 60) else { return }
        asking = true; at = now; la = lat; lo = lon
        var u = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        u.queryItems = [URLQueryItem(name: "latitude", value: String(format: "%.2f", lat)), URLQueryItem(name: "longitude", value: String(format: "%.2f", lon)),
                        URLQueryItem(name: "current", value: Weather.fields.joined(separator: ",")), URLQueryItem(name: "wind_speed_unit", value: "ms")]
        URLSession.shared.dataTask(with: u.url!) { [weak self] data, response, error in
            let c = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["current"] as? [String: Any]
            self?.queue.async {
                guard let self else { return }
                self.asking = false
                if let c, let v = Weather.values(c) { self.told = ""; self.got(v, Weather.sky(Int(v[9]))); return }
                self.at = now - 840   // again in a minute
                let why = error != nil ? "NO CONNECTION" : "OPEN-METEO ANSWERED \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                if why != self.told { self.told = why; self.said("WEATHER · " + why) }
            }
        }.resume()
    }

    /// Open-Meteo's names for Sender.space's order: TEMP °C, FEELS °C, HUMIDITY %, RAIN mm, CLOUDS %, WIND m/s, WINDDIR ° (where it
    /// comes from), PRESSURE hPa, ISDAY, CODE (WMO)
    static let fields = ["temperature_2m", "apparent_temperature", "relative_humidity_2m", "precipitation", "cloud_cover", "wind_speed_10m",
                         "wind_direction_10m", "pressure_msl", "is_day", "weather_code"]

    static func values(_ c: [String: Any]) -> [Float]? {
        let v = fields.map { (c[$0] as? NSNumber)?.floatValue }
        return v.contains(where: { $0 == nil }) ? nil : v.compactMap { $0 }
    }

    /// WMO's weather code in words (Open-Meteo's table)
    static func sky(_ code: Int) -> String {
        switch code {
        case 0: return "CLEAR"
        case 1: return "MAINLY CLEAR"
        case 2: return "PARTLY CLOUDY"
        case 3: return "OVERCAST"
        case 45, 48: return "FOG"
        case 51, 53, 55: return "DRIZZLE"
        case 56, 57: return "FREEZING DRIZZLE"
        case 61: return "LIGHT RAIN"
        case 63: return "RAIN"
        case 65: return "HEAVY RAIN"
        case 66, 67: return "FREEZING RAIN"
        case 71: return "LIGHT SNOW"
        case 73: return "SNOW"
        case 75: return "HEAVY SNOW"
        case 77: return "SNOW GRAINS"
        case 80, 81, 82: return "SHOWERS"
        case 85, 86: return "SNOW SHOWERS"
        case 95: return "THUNDERSTORM"
        case 96, 99: return "THUNDERSTORM AND HAIL"
        default: return "UNKNOWN"
        }
    }
}
