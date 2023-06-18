//
//  ViewController.swift
//  CalendarApp
//
//  Created by Wojciech Spaleniak on 17/06/2023.
//

import UIKit
import CalendarKit
import EventKit
import EventKitUI

class CalendarViewController: DayViewController {
    
    private enum Constants {
        static let title = "Calendar"
        static let newEventTitle = "New Event"
    }

    // MARK: - Pobieranie danych z systemowego kalendarza
    private let eventStore = EKEventStore()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Constants.title
        navigationController?.view.backgroundColor = .systemBackground
        requestAccessToCalendar()
        subscribeToNotifications()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = true
    }
    
    /// Metoda ta sprawdza, czy użytkownik udzielił pozwolenie na dostęp do kalendarza.
    /// IF success == true "udzielił" ELSE "nie udzielił"
    func requestAccessToCalendar() {
        eventStore.requestAccess(to: .event) { success, error in }
    }
    
    /// Metoda ta subskrybuje zdarzenie .EKEventStoreChanged.
    /// Zdarzenie to wywołuje się, gdy dokonano zmian w bazie danych kalendarza systemowego.
    func subscribeToNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeChanged(_:)),
            name: .EKEventStoreChanged,
            object: nil
        )
    }
    
    /// Metoda ta odświeża dane CalendarKit. Implementacja w DayViewController.
    /// Można by tego użyć podczas implementacji "odświeżanie przez przeciągnięcie".
    @objc func storeChanged(_ notification: Notification) {
        reloadData()
    }
    
    /// Metoda ta pobiera wszystkie eventy z kalendarza systemowego.
    /// Przerabia pobrane zdarzenia z obiektu typu  na obiekt EKEvent na typ Event, który zgodny jest z EventDescriptor.
    override func eventsForDate(_ date: Date) -> [EventDescriptor] {
        let startDate = date
        var oneDayComponents = DateComponents()
        oneDayComponents.day = 1
        
        guard let endDate = calendar.date(
            byAdding: oneDayComponents,
            to: startDate
        ) else { return [] }
        
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )
        
        let eventKitEvents = eventStore.events(matching: predicate)
        let calendarKitEvents = eventKitEvents.map(EKWrapper.init)
        return calendarKitEvents
    }
    
    // MARK: - Kliknięcie w zdarzenie
    /// Metoda wywoływana w momencie kliknięcia w wydarzenie.
    override func dayViewDidSelectEventView(_ eventView: EventView) {
        guard let ckEvent = eventView.descriptor as? EKWrapper else { return }
        presentDetailView(ckEvent.ekEvent)
    }
    
    /// Metoda pozwala wyświetlić detale wybranego wydarzenia.
    private func presentDetailView(_ ekEvent: EKEvent) {
        let eventVC = EKEventViewController()
        eventVC.event = ekEvent
        eventVC.allowsCalendarPreview = true
        eventVC.allowsEditing = true
        navigationController?.pushViewController(eventVC, animated: true)
    }
    
    // MARK: - Edytowanie przez przeciąganie
    /// Metoda wywoływana w momencie dłuższego przytrzymania palcem na wydarzeniu.
    /// Pozwala na zmianę położenia wybranego wydarzenia.
    override func dayViewDidLongPressEventView(_ eventView: EventView) {
        endEventEditing()
        guard let ckEvent = eventView.descriptor as? EKWrapper else { return }
        beginEditing(event: ckEvent, animated: true)
    }
    
    /// Metoda pozwala uaktualnić pierwotne wydarzenie po przeciągnięciu go w inne miejsce.
    /// Uaktualnia również wydarzenie w kalendarzu systemowym.
    override func dayView(dayView: DayView, didUpdate event: EventDescriptor) {
        guard let editingEvent = event as? EKWrapper else { return }
        if let originalEvent = editingEvent.editedEvent {
            editingEvent.commitEditing()
            
            /// Jeśli są tą samą instancją to obsługujemy tworzenie nowego wydarzenia.
            /// Jeśli nie są tą samą instancją to obsługujemy edycję istniejącego wydarzenia.
            /// Gdy nowy event to nie chcemy od razu zapisywać w kalendarzu systemowym, bo user może cancellować to wydarzenie.
            if originalEvent === editingEvent {
                presentEditingViewForEvent(editingEvent.ekEvent)
            } else {
                try? eventStore.save(editingEvent.ekEvent, span: .thisEvent)
            }
        }
        reloadData()
    }
    
    /// Metoda wyświetla ekran edycji wybranego wydarzenia.
    private func presentEditingViewForEvent(_ ekEvent: EKEvent) {
        let editingVC = EKEventEditViewController()
        editingVC.editViewDelegate = self
        editingVC.event = ekEvent
        editingVC.eventStore = eventStore
        present(editingVC, animated: true)
    }
    
    /// Metoda ta kończy edycję wydarzenia po kliknięciu w timeline.
    override func dayView(dayView: DayView, didTapTimelineAt date: Date) {
        endEventEditing()
    }
    
    /// Metoda ta kończy edycję wydarzenią po przeciągnięciu w prawo lub lewo.
    override func dayViewDidBeginDragging(dayView: DayView) {
        endEventEditing()
    }
    
    // MARK: - Tworzenie nowego wydarzenia
    /// Metoda wywoływana w momencie dłuższego przytrzymania palcem na timeline.
    override func dayView(dayView: DayView, didLongPressTimelineAt date: Date) {
        let newEKEvent = EKEvent(eventStore: eventStore)
        newEKEvent.calendar = eventStore.defaultCalendarForNewEvents
        
        var oneHourComponents = DateComponents()
        oneHourComponents.hour = 1
        let endDate = calendar.date(byAdding: oneHourComponents, to: date)
        
        newEKEvent.startDate = date
        newEKEvent.endDate = endDate
        newEKEvent.title = Constants.newEventTitle
        
        let newEKWrapper = EKWrapper(eventKitEvent: newEKEvent)
        newEKWrapper.editedEvent = newEKWrapper
        
        create(event: newEKWrapper, animated: true)
    }
}

// MARK: - Delegat widoku edycji wydarzenia
extension CalendarViewController: EKEventEditViewDelegate {
    /// Metoda pozwala przechwycić zdarzenie wewnątrz edycji wydarzenia.
    func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        endEventEditing()
        reloadData()
        controller.dismiss(animated: true)
    }
}
