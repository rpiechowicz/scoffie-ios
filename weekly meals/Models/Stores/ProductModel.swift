import Foundation

enum ProductCategory: String, CaseIterable, Codable {
    case vegetables = "Warzywa"
    case fruits = "Owoce"
    case meat = "Mięso"
    case fish = "Ryby"
    case bakery = "Piekarnia"
    case dairy = "Nabiał"
    case grains = "Zboża i makarony"
    case canned = "Konserwy"
    case beverages = "Napoje"
    case snacks = "Przekąski i słodycze"
    case household = "Chemia i gospodarstwo"
    case frozen = "Mrożonki"
    case spices = "Przyprawy i sosy"
    case oils = "Olej i tłuszcze"
    case alcohols = "Alkohole"
    case bakerySweets = "Cukiernia"
    case other = "Inne"
    
    var id: String { rawValue }
}

extension ProductCategory {
    /// Mapuje kategorię produktu na dział sklepu (wysokopoziomowe działy z ProductConstants)
    var defaultDepartment: String {
        switch self {
        case .vegetables: return ProductConstants.Department.vegetables
        case .fruits: return ProductConstants.Department.fruits
        case .meat: return ProductConstants.Department.meat
        case .fish: return ProductConstants.Department.fish
        case .bakery: return ProductConstants.Department.bakery
        case .dairy: return ProductConstants.Department.dairy
        case .grains: return ProductConstants.Department.grains
        case .canned: return ProductConstants.Department.canned
        case .beverages: return ProductConstants.Department.beverages
        case .snacks: return ProductConstants.Department.snacks
        case .household: return ProductConstants.Department.household
        case .frozen: return ProductConstants.Department.frozen
        case .spices: return ProductConstants.Department.spices
        case .oils: return ProductConstants.Department.oils
        case .alcohols: return ProductConstants.Department.alcohols
        case .bakerySweets: return ProductConstants.Department.bakerySweets
        case .other: return ProductConstants.Department.other
        }
    }
}
