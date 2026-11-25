import SwiftUI

struct MenuView: View {
    @EnvironmentObject var menu: Menu
    @EnvironmentObject var history: History
    @State private var search = ""
    let done: () -> Void

    var body: some View {
        Group {
            if let data = menu.data {
                let found = data.drinks.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                let drinks = found.filter { history.favorites.contains($0.name) } + found.filter { !history.favorites.contains($0.name) }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))]) {
                        ForEach(drinks) { drink in
                            NavigationLink {
                                CustomizeView(drink: drink, data: data, done: done)
                            } label: {
                                Text((history.favorites.contains(drink.name) ? "★ " : "") + drink.name)
                                    .frame(maxWidth: .infinity, minHeight: 80)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .searchable(text: $search)
            } else if let error = menu.error {
                VStack(spacing: 12) {
                    Text(error)
                    Button("Retry") { Task { await menu.load() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Menu")
        .toolbar { Button("Close", action: done) }
    }
}
