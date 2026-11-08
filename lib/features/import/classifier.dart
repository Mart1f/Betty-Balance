class Classifier {
  static const Map<String, List<String>> _rules = {
    'Nómina': [
      'payment from miss martha',
      'payment from caf ',
    ],
    'Alquiler': [
      'regie maisel',
      'uxco',
      'studapart',
    ],
    'Universidad': [
      'imt atlantique',
      'bde imt',
    ],
    'Supermercado': [
      'lidl', 'carrefour', 'intermarch', 'magasin u', 'auchan',
      'casino superm', 'g20 superm', 'coccinelle', 'elam distri',
      'vival', 'action', 'franprix', 'monoprix', 'global supermar',
      'supermar', 'loja de conveni',
    ],
    'Restaurantes': [
      'deliveroo', 'uber eats', 'mcdonald', 'kfc', 'ramen', "o'tacos",
      'piment rouge', 'noakhali', 'tacos', 'burger king', 'le delice',
      'coppa', 'dicha', 'titi parisien', 'passy', 'croq dahu',
      'chalet du pre', 'pizzas', 'le coin', 'paradise', 'kebab',
      'sodexo', 'restaur', 'brioche', 'selecta', 'le cadre',
      'delirium', 'le lutecia', 'avs exotique', 'grill', 'brasserie',
      'da diffusion', 'wine bar', 'pastelar', 'conscious', 'joe',
      'anuska', 'mohammad harun',
    ],
    'Transporte': [
      'blablacar', 'sncf', 'flixbus', 'flix se',
      'île-de-france mobilit', 'ile-de-france mobilit',
      'ecovelo', 'voi', 'bolt', 'grand reims mobilites',
      'bibus', 'deutsche bahn', 'metro de lisboa', 'reg brest',
      'estacion de autobus', 'metropolitano de lisboa',
      'wingo', 'star,', 'viacao', 'aeroporto', 'turo',
    ],
    'Salud': [
      'pharma', 'pharm ', 'aqualys', 'pisc brequigny',
      'pisc bréquigny', 'selarl', 'basic-fit', "wash'in",
      'coiffure',
    ],
    'Ocio': [
      'blockchain', 'cs.money', 'bet365', 'pathé', 'avalanche night',
      'disneyland', 'euro disney', 'le five', 'mellow', 'killer',
      'photomaton', 'musée', 'château', 'resel',
    ],
    'Viajes': [
      'airbnb', 'hotelf1', 'yotel', 'hotel brasserie',
      'leonardo hotels', 'hotel f1', 'hotelf1', 'govoyages',
    ],
    'Suscripciones': [
      'amazon prime', 'apple', 'openai', 'claude',
      'free mobile', 'bouygues telecom', 'association resel',
      'association des e', 'lydia solutions', 'rebuy',
      'cardif',
    ],
    'Ropa': [
      'new yorker', 'ar coiffure', 'bestwerkkledin', 'lvan btq',
      'aliexpress', 'fnac',
    ],
    'Transferencias': [
      "compte d'épargne", "compte d'epargne", 'épargne',
      // BNP PDFs often omit accents and apostrophes → catch all variants
      'epargne', 'livret', 'compte epargne',
      'bermudez romero', 'bermudez martin',
    ],
  };

  static String classify(String description, String type) {
    final desc = description.toLowerCase();
    final t = type.toLowerCase();

    if (t == 'interest') return 'Otros';
    if (t == 'card refund') return 'Otros';

    // Uber Eats before Uber to avoid partial match
    if (desc.contains('uber eats')) return 'Restaurantes';
    if (desc.contains('uber')) return 'Transporte';

    // Amazon Prime before Amazon
    if (desc.contains('amazon prime')) return 'Suscripciones';
    if (desc.contains('amazon')) return 'Otros';

    for (final entry in _rules.entries) {
      for (final keyword in entry.value) {
        if (desc.contains(keyword.toLowerCase())) {
          return entry.key;
        }
      }
    }

    // Outgoing person transfers
    // BNP:    "To NAME"         (from /BEN extraction)
    // Revolut:"Transfer to NAME"(normalized from "Transferencia a X")
    if (t == 'transfer' &&
        (desc.startsWith('to ') || desc.startsWith('transfer to '))) {
      return 'Personas';
    }

    // Incoming person transfers
    // BNP:    "From NAME"         (from /DE extraction)
    // Revolut:"Transfer from NAME"(normalized from "Transferencia de X")
    if (t == 'transfer' && desc.startsWith('transfer from ')) {
      return 'Personas';
    }

    // Incoming deposits from persons
    // BNP:    "From NAME"
    if (t == 'deposit' && desc.startsWith('from ')) {
      return 'Personas';
    }

    // Revolut TOPUP from person: "Payment from NAME"
    // (keyword loop already caught Nómina sources like CAF/MisMartha above)
    if (t == 'topup' && desc.startsWith('payment from ')) {
      return 'Personas';
    }

    return 'Otros';
  }
}
