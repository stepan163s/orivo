import Foundation

let urlString = "http://127.0.0.1:8090/stream/True.Detective.S01E01.WEB-DL.1080p-SOFCJ.mkv?link=bf1f315b3f90e065fb94d1c1f7f86a25798a35d1&index=1&play"
let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
if let encoded = urlString.addingPercentEncoding(withAllowedCharacters: allowedCharacters) {
    print("Encoded: \(encoded)")
} else {
    print("Encoding failed")
}
