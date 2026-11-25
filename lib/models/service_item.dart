class ServiceItem {
  final String id;
  final String name;
  final String category;
  final double? defaultIntervalKm;

  const ServiceItem({
    required this.id,
    required this.name,
    required this.category,
    this.defaultIntervalKm,
  });

  static List<ServiceItem> defaults = [
    // Масла
    ServiceItem(
      id: 'oil_engine',
      name: 'Моторное масло',
      category: 'Масла',
      defaultIntervalKm: 10000,
    ),
    ServiceItem(
      id: 'oil_transmission',
      name: 'Масло КПП',
      category: 'Масла',
      defaultIntervalKm: 60000,
    ),
    ServiceItem(
      id: 'oil_brake',
      name: 'Тормозная жидкость',
      category: 'Масла',
      defaultIntervalKm: 40000,
    ),
    ServiceItem(
      id: 'oil_power_steering',
      name: 'Масло ГУР',
      category: 'Масла',
      defaultIntervalKm: 50000,
    ),
    ServiceItem(
      id: 'oil_coolant',
      name: 'Антифриз',
      category: 'Масла',
      defaultIntervalKm: 60000,
    ),

    // Фильтры
    ServiceItem(
      id: 'filter_oil',
      name: 'Масляный фильтр',
      category: 'Фильтры',
      defaultIntervalKm: 10000,
    ),
    ServiceItem(
      id: 'filter_air',
      name: 'Воздушный фильтр',
      category: 'Фильтры',
      defaultIntervalKm: 20000,
    ),
    ServiceItem(
      id: 'filter_cabin',
      name: 'Салонный фильтр',
      category: 'Фильтры',
      defaultIntervalKm: 15000,
    ),
    ServiceItem(
      id: 'filter_fuel',
      name: 'Топливный фильтр',
      category: 'Фильтры',
      defaultIntervalKm: 30000,
    ),

    // Тормозная система
    ServiceItem(
      id: 'brake_pads_front',
      name: 'Тормозные колодки (передние)',
      category: 'Тормоза',
      defaultIntervalKm: 30000,
    ),
    ServiceItem(
      id: 'brake_pads_rear',
      name: 'Тормозные колодки (задние)',
      category: 'Тормоза',
      defaultIntervalKm: 40000,
    ),
    ServiceItem(
      id: 'brake_discs_front',
      name: 'Тормозные диски (передние)',
      category: 'Тормоза',
      defaultIntervalKm: 80000,
    ),
    ServiceItem(
      id: 'brake_discs_rear',
      name: 'Тормозные диски (задние)',
      category: 'Тормоза',
      defaultIntervalKm: 100000,
    ),

    // Шины и колёса
    ServiceItem(
      id: 'tires_summer',
      name: 'Летние шины (комплект)',
      category: 'Шины',
      defaultIntervalKm: 50000,
    ),
    ServiceItem(
      id: 'tires_winter',
      name: 'Зимние шины (комплект)',
      category: 'Шины',
      defaultIntervalKm: 50000,
    ),
    ServiceItem(
      id: 'tire_rotation',
      name: 'Ротация шин',
      category: 'Шины',
      defaultIntervalKm: 10000,
    ),

    // Прочее
    ServiceItem(
      id: 'battery',
      name: 'Аккумулятор',
      category: 'Прочее',
      defaultIntervalKm: 60000,
    ),
    ServiceItem(
      id: 'spark_plugs',
      name: 'Свечи зажигания',
      category: 'Прочее',
      defaultIntervalKm: 30000,
    ),
    ServiceItem(
      id: 'timing_belt',
      name: 'Ремень ГРМ',
      category: 'Прочее',
      defaultIntervalKm: 90000,
    ),
    ServiceItem(
      id: 'wiper_blades',
      name: 'Дворники',
      category: 'Прочее',
      defaultIntervalKm: 15000,
    ),
  ];
}

class TireItem {
  static const List<String> names = [
    'Летние шины',
    'Зимние шины',
    'Ротация шин',
  ];
}

class TaxItem {
  static const List<String> names = ['Транспортный налог'];
}

class InsuranceItem {
  static const List<String> names = ['ОСАГО', 'КАСКО', 'ДСАГО'];
}

class WashItem {
  static const List<String> names = [
    'Ручная мойка',
    'Бесконтактная мойка',
    'Мойка самообслуживания',
    'Автоматическая мойка',
  ];
}

class GosuslugiItem {
  static const List<String> names = [
    'Техосмотр',
    'Постановка на учёт',
    'Снятие с учёта',
    'Замена номеров',
    'Замена прав',
    'Госпошлина',
    'Штрафы',
  ];
}

class ServiceGroup {
  final String title;
  final List<ServiceItem> items;

  const ServiceGroup({required this.title, required this.items});
}

class UserService {
  final String id;
  final String groupTitle;
  final String name;

  UserService({required this.id, required this.groupTitle, required this.name});

  factory UserService.fromMap(Map<String, dynamic> map, String id) {
    return UserService(
      id: id,
      groupTitle: map['groupTitle'] ?? '',
      name: map['name'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {'groupTitle': groupTitle, 'name': name};
  }
}

class ServiceCatalog {
  static const List<ServiceGroup> groups = [
    ServiceGroup(
      title: 'Масла и жидкости',
      items: [
        ServiceItem(
          id: 'oil_engine',
          name: 'Моторное масло',
          category: 'Масла',
        ),
        ServiceItem(
          id: 'oil_transmission',
          name: 'Масло КПП',
          category: 'Масла',
        ),
        ServiceItem(
          id: 'oil_brake',
          name: 'Тормозная жидкость',
          category: 'Масла',
        ),
        ServiceItem(
          id: 'oil_power_steering',
          name: 'Масло ГУР',
          category: 'Масла',
        ),
        ServiceItem(id: 'oil_coolant', name: 'Антифриз', category: 'Масла'),
        ServiceItem(
          id: 'oil_differential',
          name: 'Масло редуктора',
          category: 'Масла',
        ),
      ],
    ),
    ServiceGroup(
      title: 'Фильтры',
      items: [
        ServiceItem(
          id: 'filter_oil',
          name: 'Масляный фильтр',
          category: 'Фильтры',
        ),
        ServiceItem(
          id: 'filter_air',
          name: 'Воздушный фильтр',
          category: 'Фильтры',
        ),
        ServiceItem(
          id: 'filter_cabin',
          name: 'Салонный фильтр',
          category: 'Фильтры',
        ),
        ServiceItem(
          id: 'filter_fuel',
          name: 'Топливный фильтр',
          category: 'Фильтры',
        ),
      ],
    ),
    ServiceGroup(
      title: 'Тормоза',
      items: [
        ServiceItem(
          id: 'brake_pads_front',
          name: 'Тормозные колодки (передние)',
          category: 'Тормоза',
        ),
        ServiceItem(
          id: 'brake_pads_rear',
          name: 'Тормозные колодки (задние)',
          category: 'Тормоза',
        ),
        ServiceItem(
          id: 'brake_discs_front',
          name: 'Тормозные диски (передние)',
          category: 'Тормоза',
        ),
        ServiceItem(
          id: 'brake_discs_rear',
          name: 'Тормозные диски (задние)',
          category: 'Тормоза',
        ),
        ServiceItem(
          id: 'brake_calipers',
          name: 'Тормозные суппорты',
          category: 'Тормоза',
        ),
      ],
    ),
    ServiceGroup(
      title: 'Подвеска и рулевое',
      items: [
        ServiceItem(
          id: 'shock_absorbers',
          name: 'Амортизаторы',
          category: 'Подвеска',
        ),
        ServiceItem(id: 'springs', name: 'Пружины', category: 'Подвеска'),
        ServiceItem(
          id: 'ball_joints',
          name: 'Шаровые опоры',
          category: 'Подвеска',
        ),
        ServiceItem(id: 'tie_rods', name: 'Рулевые тяги', category: 'Подвеска'),
        ServiceItem(
          id: 'tie_rod_ends',
          name: 'Рулевые наконечники',
          category: 'Подвеска',
        ),
        ServiceItem(
          id: 'wheel_bearings',
          name: 'Ступичные подшипники',
          category: 'Подвеска',
        ),
        ServiceItem(
          id: 'stabilizer_links',
          name: 'Стойки стабилизатора',
          category: 'Подвеска',
        ),
        ServiceItem(
          id: 'silent_blocks',
          name: 'Сайлентблоки',
          category: 'Подвеска',
        ),
      ],
    ),
    ServiceGroup(
      title: 'Двигатель',
      items: [
        ServiceItem(
          id: 'spark_plugs',
          name: 'Свечи зажигания',
          category: 'Двигатель',
        ),
        ServiceItem(
          id: 'timing_belt',
          name: 'Ремень ГРМ',
          category: 'Двигатель',
        ),
        ServiceItem(
          id: 'timing_chain',
          name: 'Цепь ГРМ',
          category: 'Двигатель',
        ),
        ServiceItem(
          id: 'water_pump',
          name: 'Помпа (водяной насос)',
          category: 'Двигатель',
        ),
        ServiceItem(id: 'thermostat', name: 'Термостат', category: 'Двигатель'),
        ServiceItem(
          id: 'engine_mounts',
          name: 'Подушки двигателя',
          category: 'Двигатель',
        ),
      ],
    ),
    ServiceGroup(
      title: 'Трансмиссия',
      items: [
        ServiceItem(
          id: 'atf_change',
          name: 'Замена масла АКПП',
          category: 'Трансмиссия',
        ),
        ServiceItem(
          id: 'atf_filter',
          name: 'Фильтр АКПП',
          category: 'Трансмиссия',
        ),
        ServiceItem(id: 'cv_joints', name: 'ШРУСы', category: 'Трансмиссия'),
        ServiceItem(
          id: 'drive_boots',
          name: 'Пыльники приводов',
          category: 'Трансмиссия',
        ),
      ],
    ),
    ServiceGroup(
      title: 'Электрика и кондиционер',
      items: [
        ServiceItem(id: 'battery', name: 'Аккумулятор', category: 'Электрика'),
        ServiceItem(id: 'alternator', name: 'Генератор', category: 'Электрика'),
        ServiceItem(id: 'starter', name: 'Стартер', category: 'Электрика'),
        ServiceItem(id: 'lamps', name: 'Лампы / фары', category: 'Электрика'),
        ServiceItem(
          id: 'ac_service',
          name: 'Заправка кондиционера',
          category: 'Электрика',
        ),
      ],
    ),
    ServiceGroup(
      title: 'Прочее',
      items: [
        ServiceItem(id: 'wiper_blades', name: 'Дворники', category: 'Прочее'),
        ServiceItem(id: 'diagnostics', name: 'Диагностика', category: 'Прочее'),
        ServiceItem(
          id: 'body_repair',
          name: 'Кузовной ремонт',
          category: 'Прочее',
        ),
        ServiceItem(
          id: 'exhaust',
          name: 'Выхлопная система',
          category: 'Прочее',
        ),
      ],
    ),
  ];
}
