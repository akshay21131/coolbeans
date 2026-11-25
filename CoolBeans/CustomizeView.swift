import SwiftUI

struct CustomizeView: View {
    @EnvironmentObject var history: History
    let drink: Drink
    let data: MenuData
    var editing: Serving?   // set when editing a saved serving
    let done: () -> Void

    @State private var size: Size
    @State private var shots: Int
    @State private var decaf: Bool
    @State private var milk: Option?
    @State private var syrup: Option?

    init(drink: Drink, data: MenuData, editing: Serving? = nil, done: @escaping () -> Void) {
        self.drink = drink
        self.data = data
        self.editing = editing
        self.done = done
        _size = State(initialValue: editing?.size ?? .medium)
        _shots = State(initialValue: editing?.shots ?? 0)
        _decaf = State(initialValue: editing?.decaf ?? false)
        _milk = State(initialValue: data.milks.first { $0.name == editing?.milk })
        _syrup = State(initialValue: data.syrups.first { $0.name == editing?.syrup })
    }

    // Rough estimates: 75 mg caffeine and 5 kcal per extra shot; decaf keeps ~3%.
    private var serving: Serving {
        let caffeine = (Double(drink.caffeine) * size.scale + Double(shots * 75)) * (decaf ? 0.03 : 1)
        let calories = Double(drink.calories) * size.scale + Double(shots * 5)
            + Double((milk?.calories ?? 0) + (syrup?.calories ?? 0))
        var s = Serving(drink: drink.name, size: size, shots: shots, decaf: decaf,
                        milk: milk?.name ?? "None", syrup: syrup?.name ?? "None",
                        caffeine: Int(caffeine), calories: Int(calories))
        if let editing { s.id = editing.id; s.date = editing.date }
        return s
    }

    var body: some View {
        Form {
            Picker("Size", selection: $size) {
                ForEach(Size.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            Stepper("Extra shots: \(shots)", value: $shots, in: 0...4)
            Toggle("Decaf", isOn: $decaf)
            Picker("Milk", selection: $milk) {
                Text("None").tag(Option?.none)
                ForEach(data.milks) { Text($0.name).tag(Optional($0)) }
            }
            Picker("Syrup", selection: $syrup) {
                Text("None").tag(Option?.none)
                ForEach(data.syrups) { Text($0.name).tag(Optional($0)) }
            }
            Section("Estimate") {
                LabeledContent("Caffeine", value: "\(serving.caffeine) mg")
                LabeledContent("Calories", value: "\(serving.calories) kcal")
            }
        }
        .navigationTitle(drink.name)
        .toolbar {
            ToolbarItemGroup {
                Button("Favorite", systemImage: history.favorites.contains(drink.name) ? "star.fill" : "star") {
                    history.toggleFavorite(drink.name)
                }
                Button("Save") {
                    if editing == nil { history.add(serving) } else { history.update(serving) }
                    done()
                }
            }
        }
    }
}
