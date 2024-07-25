//
//  BaseViewModel.swift
//  SRNetworkLayer
//
//  Created by Siamak on 8/26/23.
//

import Combine
import Foundation
import UIKit

// MARK: - BaseViewModel

class BaseViewModel {
    // MARK: Lifecycle

    init() {
        bindNetworkError()
    }

    deinit {
        cancellableSet.forEach { $0.cancel() }
        cancellableSet.removeAll()
    }

    // MARK: Internal

    @Inject var remoteRepositories: NetworkRepositories
    var error = CurrentValueSubject<NetworkError?, Never>(nil)

    // MARK: Private

    private var cancellableSet = Set<AnyCancellable>()
}

extension BaseViewModel {
    private func bindNetworkError() {
        self.error.subscribe(on: DispatchQueue.main)
            .sink { [weak self] errors in
                guard let _ = self, let errors = errors else {
                    return
                }
                guard let window = UIApplication.shared.windows.first(where: \.isKeyWindow) else {
                    return
                }
                let controller = (window.rootViewController)
                controller?.showErrorAlert(title: "Error", message: errors.errorDescription ?? "")
            }
            .store(in: &self.cancellableSet)
    }
}
