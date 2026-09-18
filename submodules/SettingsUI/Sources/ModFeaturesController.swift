import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class ModFeaturesControllerArguments {
    let toggleAntiDelete: (Bool) -> Void
    let toggleCallRecorder: (Bool) -> Void
    let toggleSaveToSavedMessages: (Bool) -> Void
    
    init(
        toggleAntiDelete: @escaping (Bool) -> Void,
        toggleCallRecorder: @escaping (Bool) -> Void,
        toggleSaveToSavedMessages: @escaping (Bool) -> Void
    ) {
        self.toggleAntiDelete = toggleAntiDelete
        self.toggleCallRecorder = toggleCallRecorder
        self.toggleSaveToSavedMessages = toggleSaveToSavedMessages
    }
}

private enum ModFeaturesSection: Int32 {
    case messages
    case calls
}

private enum ModFeaturesEntry: ItemListNodeEntry {
    case messagesHeader
    case antiDelete(Bool)
    case messagesFooter
    
    case callsHeader
    case callRecorder(Bool)
    case saveToSavedMessages(value: Bool, enabled: Bool)
    case callsFooter
    
    var section: ItemListSectionId {
        switch self {
        case .messagesHeader, .antiDelete, .messagesFooter:
            return ModFeaturesSection.messages.rawValue
        case .callsHeader, .callRecorder, .saveToSavedMessages, .callsFooter:
            return ModFeaturesSection.calls.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
        case .messagesHeader:
            return 0
        case .antiDelete:
            return 1
        case .messagesFooter:
            return 2
        case .callsHeader:
            return 3
        case .callRecorder:
            return 4
        case .saveToSavedMessages:
            return 5
        case .callsFooter:
            return 6
        }
    }
    
    static func <(lhs: ModFeaturesEntry, rhs: ModFeaturesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ModFeaturesControllerArguments
        switch self {
        case .messagesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "СООБЩЕНИЯ", sectionId: self.section)
        case let .antiDelete(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Сохранять удаленные", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleAntiDelete(value)
            })
        case .messagesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Входящие сообщения, удаленные собеседником, сохраняются в чате с пометкой [Удалено]."), sectionId: self.section)
        case .callsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЗВОНКИ", sectionId: self.section)
        case let .callRecorder(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Запись звонков", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleCallRecorder(value)
            })
        case let .saveToSavedMessages(value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Отправлять в Избранное", value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleSaveToSavedMessages(value)
            })
        case .callsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Аудиозапись входящих и исходящих звонков объединяет звук обоих собеседников и сохраняется прямо в чат «Избранное»."), sectionId: self.section)
        }
    }
}

private struct ModFeaturesState: Equatable {
    var antiDeleteEnabled: Bool
    var callRecorderEnabled: Bool
    var saveToSavedMessages: Bool
}

private func modFeaturesEntries(presentationData: PresentationData, state: ModFeaturesState) -> [ModFeaturesEntry] {
    var entries: [ModFeaturesEntry] = []
    
    entries.append(.messagesHeader)
    entries.append(.antiDelete(state.antiDeleteEnabled))
    entries.append(.messagesFooter)
    
    entries.append(.callsHeader)
    entries.append(.callRecorder(state.callRecorderEnabled))
    entries.append(.saveToSavedMessages(value: state.saveToSavedMessages, enabled: state.callRecorderEnabled))
    entries.append(.callsFooter)
    
    return entries
}

public func modFeaturesController(context: AccountContext) -> ViewController {
    let initialState = ModFeaturesState(
        antiDeleteEnabled: UserDefaults.standard.object(forKey: "tg_mod_anti_delete_enabled") as? Bool ?? true,
        callRecorderEnabled: UserDefaults.standard.object(forKey: "tg_mod_call_recorder_enabled") as? Bool ?? true,
        saveToSavedMessages: UserDefaults.standard.object(forKey: "tg_mod_call_record_to_saved_messages") as? Bool ?? true
    )
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    
    let updateState: ((ModFeaturesState) -> ModFeaturesState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
    let arguments = ModFeaturesControllerArguments(
        toggleAntiDelete: { value in
            UserDefaults.standard.set(value, forKey: "tg_mod_anti_delete_enabled")
            updateState { current in
                var current = current
                current.antiDeleteEnabled = value
                return current
            }
        },
        toggleCallRecorder: { value in
            UserDefaults.standard.set(value, forKey: "tg_mod_call_recorder_enabled")
            updateState { current in
                var current = current
                current.callRecorderEnabled = value
                return current
            }
        },
        toggleSaveToSavedMessages: { value in
            UserDefaults.standard.set(value, forKey: "tg_mod_call_record_to_saved_messages")
            updateState { current in
                var current = current
                current.saveToSavedMessages = value
                return current
            }
        }
    )
    
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)
        
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Функции мода"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: modFeaturesEntries(presentationData: presentationData, state: state),
            style: .blocks,
            animateChanges: true
        )
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    return controller
}
