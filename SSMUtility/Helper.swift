//
//  Helper.swift
//  SSMUtility
//
//  Created by Tushar Chitnavis on 26/12/21.
//


import Foundation
import UIKit
import AVFoundation

// MARK: - Feature Selection

enum FacialFeature: String, CaseIterable {
    case skin = "Skin"
    case hair = "Hair"
    case teeth = "Teeth"
    case glasses = "Glasses"
    
    var icon: String {
        switch self {
        case .skin: return "face.smiling"
        case .hair: return "person.crop.circle"
        case .teeth: return "mouth"
        case .glasses: return "eyeglasses"
        }
    }
    
    var matteType: AVSemanticSegmentationMatte.MatteType {
        switch self {
        case .skin: return .skin
        case .hair: return .hair
        case .teeth: return .teeth
        case .glasses: return .glasses
        }
    }
}

class Helper: NSObject {

    static let sharedInstance = Helper()
    var selectedImage: UIImage?
    var segmentationImageArray = [UIImage]()
    
    // Feature selection - default to all features enabled
    var selectedFeatures: Set<FacialFeature> = Set(FacialFeature.allCases)
    
    var selectedMatteTypes: [AVSemanticSegmentationMatte.MatteType] {
        return selectedFeatures.map { $0.matteType }
    }
    
    func isFeatureSelected(_ feature: FacialFeature) -> Bool {
        return selectedFeatures.contains(feature)
    }
    
    func toggleFeature(_ feature: FacialFeature) {
        if selectedFeatures.contains(feature) {
            selectedFeatures.remove(feature)
        } else {
            selectedFeatures.insert(feature)
        }
    }
    
    func selectAllFeatures() {
        selectedFeatures = Set(FacialFeature.allCases)
    }
    
    var areAllFeaturesSelected: Bool {
        return selectedFeatures.count == FacialFeature.allCases.count
    }
}
