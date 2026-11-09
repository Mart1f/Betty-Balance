import 'ml_classifier.dart';

class Classifier {
  static const Map<String, List<String>> _rules = {
    'Salary': [
      'payment from miss martha',
      'payment from caf ',
      'taack',
    ],
    'Rent': [
      'regie maisel',
      'uxco',
      'studapart',
    ],
    'University': [
      'imt atlantique',
      'bde imt',
    ],
    'Groceries': [
      'lidl', 'carrefour', 'intermarch', 'magasin u', 'auchan',
      'casino superm', 'g20 superm', 'coccinelle', 'elam distri',
      'vival', 'action', 'franprix', 'monoprix', 'global supermar',
      'supermar', 'loja de conveni',
    ],
    'Restaurants': [
      'deliveroo', 'uber eats', 'mcdonald', 'kfc', 'ramen', "o'tacos",
      'piment rouge', 'noakhali', 'tacos', 'burger king', 'le delice',
      'coppa', 'dicha', 'titi parisien', 'passy', 'croq dahu',
      'chalet du pre', 'pizzas', 'le coin', 'paradise', 'kebab',
      'sodexo', 'restaur', 'brioche', 'selecta', 'le cadre',
      'delirium', 'le lutecia', 'avs exotique', 'grill', 'brasserie',
      'da diffusion', 'wine bar', 'pastelar', 'conscious', 'joe',
      'anuska', 'mohammad harun',
    ],
    'Transport': [
      'blablacar', 'sncf', 'flixbus', 'flix se',
      'île-de-france mobilit', 'ile-de-france mobilit',
      'ile de france mobilit', 'idf mobilit',
      'île-de-france mobilit', 'mobilitã',
      'navigo', 'pass navigo', 'service navigo',
      'ecovelo', 'voi', 'bolt', 'grand reims mobilites',
      'bibus', 'deutsche bahn', 'metro de lisboa', 'reg brest',
      'estacion de autobus', 'metropolitano de lisboa',
      'wingo', 'star,', 'viacao', 'aeroporto', 'turo',
    ],
    'Health': [
      'pharma', 'pharm ', 'aqualys', 'pisc brequigny',
      'pisc bréquigny', 'selarl', 'basic-fit', "wash'in",
      'coiffure',
    ],
    'Entertainment': [
      'blockchain', 'cs.money', 'bet365', 'pathé', 'avalanche night',
      'disneyland', 'euro disney', 'le five', 'mellow', 'killer',
      'photomaton', 'musée', 'château', 'resel',
    ],
    'Travel': [
      'airbnb', 'hotelf1', 'yotel', 'hotel brasserie',
      'leonardo hotels', 'hotel f1', 'hotelf1', 'govoyages',
    ],
    'Subscriptions': [
      'amazon prime', 'apple', 'openai', 'claude', 'anthropic',
      'free mobile', 'bouygues telecom', 'association resel',
      'association des e', 'lydia solutions', 'rebuy',
      'cardif',
    ],
    'Clothing': [
      'new yorker', 'ar coiffure', 'bestwerkkledin', 'lvan btq',
      'aliexpress', 'fnac',
    ],
    'Transfers': [
      "compte d'épargne", "compte d'epargne", "compte d’épargne", "compte d’epargne",
      'épargne', 'epargne', 'livret', 'compte epargne',
      'bermudez romero', 'bermudez martin',
    ],
  };

  static String classify(String description, String type) {
    final desc = description.toLowerCase();
    final t = type.toLowerCase();

    if (t == 'interest') return 'Others';
    if (t == 'card refund') return 'Others';

    if (desc.contains('uber eats') || desc.contains('uber *eats')) return 'Restaurants';
    if (desc.contains('uber')) return 'Transport';

    if (desc.contains('amazon prime')) return 'Subscriptions';
    if (desc.contains('amazon')) return 'Others';

    for (final entry in _rules.entries) {
      for (final keyword in entry.value) {
        if (desc.contains(keyword.toLowerCase())) {
          return entry.key;
        }
      }
    }

    if (t == 'transfer' &&
        (desc.startsWith('to ') || desc.startsWith('transfer to '))) {
      return 'People';
    }

    if (t == 'transfer' && desc.startsWith('transfer from ')) {
      return 'People';
    }

    if (t == 'deposit' && desc.startsWith('from ')) {
      return 'People';
    }

    if ((t == 'topup' || t == 'transfer') && desc.startsWith('payment from ')) {
      return 'People';
    }

    return MlClassifier.predict(description) ?? 'Others';
  }
}
