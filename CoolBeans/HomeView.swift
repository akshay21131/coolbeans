import SwiftUI
import Charts

struct HomeView: View {
    @EnvironmentObject var history: History
    @EnvironmentObject var menu: Menu
    @AppStorage("reminder") private var reminder = false
    @State private var showMenu = false
    @State private var editing: Serving?
    private let limit = 400 // mg of caffeine per day

    private var week: [Date] { (0..<7).map { Calendar.current.date(byAdding: .day, value: -$0, to: .now)! }.reversed() }
    private var days: [Date] {
        Set(history.servings.map { Calendar.current.startOfDay(for: $0.date) }).sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    LabeledContent("Caffeine", value: "\(history.caffeine) mg / \(limit)")
                        .foregroundStyle(history.caffeine > limit ? .red : .primary)
                    LabeledContent("Calories", value: "\(history.calories) kcal")
                }
                Section("Last 7 days (mg)") {
                    Chart {
                        ForEach(week, id: \.self) {
                            BarMark(x: .value("Day", $0, unit: .day), y: .value("mg", history.caffeine(on: $0)))
                        }
                        RuleMark(y: .value("Limit", limit)).foregroundStyle(.red)
                    }
                    .frame(height: 120)
                }
                ForEach(days, id: \.self) { day in
                    Section("\(day.formatted(.dateTime.month().day())) · \(history.caffeine(on: day)) mg") {
                        ForEach(history.on(day)) { s in
                            VStack(alignment: .leading) {
                                Text("\(s.drink) (\(s.size.rawValue))").font(.headline)
                                Text("\(s.caffeine) mg · \(s.calories) kcal").font(.caption)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { edit(s) }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) { history.delete(s) }
                            }
                            .swipeActions(edge: .leading) {
                                Button("Repeat") { history.repeatServing(s) }.tint(.green)
                            }
                        }
                    }
                }
                Section {
                    Toggle("2 PM caffeine cutoff reminder", isOn: $reminder)
                        .onChange(of: reminder) { Reminder.set(reminder) }
                }
            }
            .navigationTitle("CoolBeans")
            .toolbar { Button("Add", systemImage: "plus") { showMenu = true } }
            .sheet(isPresented: $showMenu) {
                NavigationStack { MenuView(done: { showMenu = false }) }
            }
            .sheet(item: $editing) { s in
                NavigationStack {
                    if let data = menu.data, let drink = data.drinks.first(where: { $0.name == s.drink }) {
                        CustomizeView(drink: drink, data: data, editing: s, done: { editing = nil })
                    }
                }
            }
        }
    }

    // Only drinks still on the menu can be edited.
    private func edit(_ s: Serving) {
        if menu.data?.drinks.contains(where: { $0.name == s.drink }) == true { editing = s }
    }
}
