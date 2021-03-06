/// Copyright (c) 2020 Razeware LLC
/// 
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
/// 
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
/// 
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
/// 
/// This project and source code may use libraries or frameworks that are
/// released under various Open-Source licenses. Use of those libraries and
/// frameworks are governed by their own individual licenses.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import MapKit
import CoreLocation

class RouteSelectionViewController: UIViewController {
  @IBOutlet private var inputContainerView: UIView!
  @IBOutlet private var originTextField: UITextField!
  @IBOutlet private var stopTextField: UITextField!
  @IBOutlet private var extraStopTextField: UITextField!
  @IBOutlet private var calculateButton: UIButton!
  @IBOutlet private var activityIndicatorView: UIActivityIndicatorView!
  @IBOutlet private var keyboardAvoidingConstraint: NSLayoutConstraint!

  @IBOutlet private var suggestionLabel: UILabel!
  @IBOutlet private var suggestionContainerView: UIView!
  @IBOutlet private var suggestionContainerTopConstraint: NSLayoutConstraint!

  private var editingTextField: UITextField?
  private var currentRegion: MKCoordinateRegion?
  private var currentPlace: CLPlacemark?

  private let locationManager = CLLocationManager()
  private let completer = MKLocalSearchCompleter()

  private let defaultAnimationDuration: TimeInterval = 0.25

  override func viewDidLoad() {
    super.viewDidLoad()

    suggestionContainerView.addBorder()
    inputContainerView.addBorder()
    calculateButton.stylize()

    completer.delegate = self

    beginObserving()
    configureGestures()
    configureTextFields()
    attemptLocationAccess()
    hideSuggestionView(animated: false)
  }

  // MARK: - Helpers

  private func configureGestures() {
    view.addGestureRecognizer(
      UITapGestureRecognizer(
        target: self,
        action: #selector(handleTap(_:))
      )
    )
    suggestionContainerView.addGestureRecognizer(
      UITapGestureRecognizer(
        target: self,
        action: #selector(suggestionTapped(_:))
      )
    )
  }

  private func configureTextFields() {
    originTextField.delegate = self
    stopTextField.delegate = self
    extraStopTextField.delegate = self

    originTextField.addTarget(
      self,
      action: #selector(textFieldDidChange(_:)),
      for: .editingChanged
    )
    stopTextField.addTarget(
      self,
      action: #selector(textFieldDidChange(_:)),
      for: .editingChanged
    )
    extraStopTextField.addTarget(
      self,
      action: #selector(textFieldDidChange(_:)),
      for: .editingChanged
    )
  }

  private func attemptLocationAccess() {
    guard CLLocationManager.locationServicesEnabled() else {
      return
    }

    locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    locationManager.delegate = self

    if CLLocationManager.authorizationStatus() == .notDetermined {
      locationManager.requestWhenInUseAuthorization()
    } else {
      locationManager.requestLocation()
    }
  }

  private func hideSuggestionView(animated: Bool) {
    suggestionContainerTopConstraint.constant = -1 * (suggestionContainerView.bounds.height + 1)

    guard animated else {
      view.layoutIfNeeded()
      return
    }

    UIView.animate(withDuration: defaultAnimationDuration) {
      self.view.layoutIfNeeded()
    }
  }

  private func showSuggestion(_ suggestion: String) {
    suggestionLabel.text = suggestion
    suggestionContainerTopConstraint.constant = -4 // to hide the top corners

    UIView.animate(withDuration: defaultAnimationDuration) {
      self.view.layoutIfNeeded()
    }
  }

  private func presentAlert(message: String) {
    let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    alertController.addAction(UIAlertAction(title: "Okay", style: .default, handler: nil))

    present(alertController, animated: true)
  }

  // MARK: - Actions

  @objc private func textFieldDidChange(_ field: UITextField) {
    if field == originTextField && currentPlace != nil {
      currentPlace = nil
      field.text = ""
    }

    guard let query = field.contents else {
      hideSuggestionView(animated: true)

      if completer.isSearching {
        completer.cancel()
      }
      return
    }

    completer.queryFragment = query
  }

  @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
    let gestureView = gesture.view
    let point = gesture.location(in: gestureView)

    guard
      let hitView = gestureView?.hitTest(point, with: nil),
      hitView == gestureView
      else {
        return
    }

    view.endEditing(true)
  }

  @objc private func suggestionTapped(_ gesture: UITapGestureRecognizer) {
    hideSuggestionView(animated: true)

    editingTextField?.text = suggestionLabel.text
    editingTextField = nil
  }

  @IBAction private func calculateButtonTapped() {
    view.endEditing(true)

    calculateButton.isEnabled = false
    activityIndicatorView.startAnimating()

    let segment: RouteBuilder.Segment?
    if let currentLocation = currentPlace?.location {
      segment = .location(currentLocation)
    } else if let originValue = originTextField.contents {
      segment = .text(originValue)
    } else {
      segment = nil
    }

    let stopSegments: [RouteBuilder.Segment] = [
      stopTextField.contents,
      extraStopTextField.contents
    ]
    .compactMap { contents in
      if let value = contents {
        return .text(value)
      } else {
        return nil
      }
    }

    guard
      let originSegment = segment,
      !stopSegments.isEmpty
      else {
        presentAlert(message: "Please select an origin and at least 1 stop.")
        activityIndicatorView.stopAnimating()
        calculateButton.isEnabled = true
        return
    }

    RouteBuilder.buildRoute(
      origin: originSegment,
      stops: stopSegments,
      within: currentRegion
    ) { result in
      self.calculateButton.isEnabled = true
      self.activityIndicatorView.stopAnimating()

      switch result {
      case .success(let route):
        let viewController = DirectionsViewController(route: route)
        self.present(viewController, animated: true)

      case .failure(let error):
        let errorMessage: String

        switch error {
        case .invalidSegment(let reason):
          errorMessage = "There was an error with: \(reason)."
        }

        self.presentAlert(message: errorMessage)
      }
    }
  }

  // MARK: - Notifications

  private func beginObserving() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleKeyboardFrameChange(_:)),
      name: UIResponder.keyboardWillChangeFrameNotification,
      object: nil
    )
  }

  @objc private func handleKeyboardFrameChange(_ notification: Notification) {
    guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
      return
    }

    let viewHeight = view.bounds.height - view.safeAreaInsets.bottom
    let visibleHeight = viewHeight - frame.origin.y
    keyboardAvoidingConstraint.constant = visibleHeight + 32

    UIView.animate(withDuration: defaultAnimationDuration) {
      self.view.layoutIfNeeded()
    }
  }
}

// MARK: - UITextFieldDelegate

extension RouteSelectionViewController: UITextFieldDelegate {
  func textFieldDidBeginEditing(_ textField: UITextField) {
    hideSuggestionView(animated: true)

    if completer.isSearching {
      completer.cancel()
    }

    editingTextField = textField
  }
}

// MARK: - CLLocationManagerDelegate

extension RouteSelectionViewController: CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    guard status == .authorizedWhenInUse else {
      return
    }

    manager.requestLocation()
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let firstLocation = locations.first else {
      return
    }

    let commonDelta: CLLocationDegrees = 25 / 111 // 1/111 = 1 latitude km
    let span = MKCoordinateSpan(latitudeDelta: commonDelta, longitudeDelta: commonDelta)
    let region = MKCoordinateRegion(center: firstLocation.coordinate, span: span)

    currentRegion = region
    completer.region = region

    CLGeocoder().reverseGeocodeLocation(firstLocation) { places, _ in
      guard let firstPlace = places?.first, self.originTextField.contents == nil else {
        return
      }

      self.currentPlace = firstPlace
      self.originTextField.text = firstPlace.abbreviation
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("Error requesting location: \(error.localizedDescription)")
  }
}

// MARK: - MKLocalSearchCompleterDelegate

extension RouteSelectionViewController: MKLocalSearchCompleterDelegate {
  func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
    guard let firstResult = completer.results.first else {
      return
    }

    showSuggestion(firstResult.title)
  }

  func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
    print("Error suggesting a location: \(error.localizedDescription)")
  }
}
