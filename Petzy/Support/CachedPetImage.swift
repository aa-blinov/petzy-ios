import SwiftUI

/// Фото питомца из сети с памятью на сессию. Состояние живёт внутри и
/// привязано к адресу вызовом `.id(url)`: смена питомца пересоздаёт вьюху
/// вместе с состоянием, и чужое фото не мигает на месте нового.
struct CachedPetImage: View {
    let url: URL

    @State private var data: Data?

    var body: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color.clear
                .task(id: url) {
                    data = await PetPhotoLoader.shared.imageData(for: url)
                }
        }
    }
}
