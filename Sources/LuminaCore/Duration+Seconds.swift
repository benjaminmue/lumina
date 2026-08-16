import Foundation

public extension Duration {
    /// Dauer in Sekunden als Gleitkommazahl.
    ///
    /// `components` liefert Sekunden und Attosekunden getrennt; die Umrechnung von
    /// Hand an jeder Aufrufstelle liest sich schlecht und wurde zweimal gebraucht.
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
