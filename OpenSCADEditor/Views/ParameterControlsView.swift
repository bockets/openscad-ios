import SwiftUI

/// Renders the document's parameters grouped into sections, one control per
/// parameter based on its `ScadControl` type.
struct ParameterControlsView: View {
    @ObservedObject var document: ScadDocument

    var body: some View {
        Form {
            ForEach(document.groups) { group in
                Section(group.name) {
                    ForEach(group.parameters) { parameter in
                        ParameterRow(document: document, parameter: parameter)
                    }
                }
            }
            if document.groups.isEmpty {
                Section {
                    Text("No customizer parameters found in this file.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A single editable parameter row.
private struct ParameterRow: View {
    @ObservedObject var document: ScadDocument
    let parameter: ScadParameter

    var body: some View {
        switch parameter.control {
        case .slider(let min, let max, let step):
            sliderRow(min: min, max: max, step: step)
        case .number:
            numberRow
        case .toggle:
            Toggle(parameter.name, isOn: boolBinding)
        case .text:
            LabeledContent(parameter.name) {
                TextField(parameter.name, text: stringBinding)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
            }
        case .numberChoice(let options, let labels):
            Picker(parameter.name, selection: numberChoiceBinding) {
                ForEach(Array(zip(options, labels)), id: \.0) { option, label in
                    Text(label).tag(option)
                }
            }
        case .stringChoice(let options, let labels):
            Picker(parameter.name, selection: stringChoiceBinding) {
                ForEach(Array(zip(options, labels)), id: \.0) { option, label in
                    Text(label).tag(option)
                }
            }
        }
    }

    private func sliderRow(min: Double, max: Double, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(parameter.name)
                Spacer()
                Text(format(currentNumber))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: doubleBinding, in: min...max, step: step > 0 ? step : 0.001)
        }
    }

    private var numberRow: some View {
        LabeledContent(parameter.name) {
            TextField(parameter.name, value: doubleBinding, format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
        }
    }

    // MARK: - Current values

    private var currentNumber: Double {
        if case .number(let n) = parameter.value { return n }
        return 0
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.3g", value)
    }

    // MARK: - Bindings

    private var doubleBinding: Binding<Double> {
        Binding(
            get: { currentNumber },
            set: { document.update(parameter, to: .number($0)) }
        )
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { if case .bool(let b) = parameter.value { return b }; return false },
            set: { document.update(parameter, to: .bool($0)) }
        )
    }

    private var stringBinding: Binding<String> {
        Binding(
            get: { if case .string(let s) = parameter.value { return s }; return "" },
            set: { document.update(parameter, to: .string($0)) }
        )
    }

    private var numberChoiceBinding: Binding<Double> {
        Binding(
            get: { currentNumber },
            set: { document.update(parameter, to: .number($0)) }
        )
    }

    private var stringChoiceBinding: Binding<String> {
        Binding(
            get: { if case .string(let s) = parameter.value { return s }; return "" },
            set: { document.update(parameter, to: .string($0)) }
        )
    }
}
