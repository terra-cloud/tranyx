// Shared Enums for Tranyx

enum JobCategory {
  electrician(
    1,
    'Electrician',
    'Installs, maintains, and repairs electrical systems and wiring.',
    'zap',
  ),
  plumber(
    2,
    'Plumber',
    'Fixes and installs water pipes, drains, and plumbing fixtures.',
    'droplet',
  ),
  mason(
    16,
    'Mason / Concrete Worker',
    'Builds and repairs walls, floors, and structures using cement, bricks, blocks, and concrete.',
    'hammer',
  ),
  carpenter(
    3,
    'Carpenter',
    'Builds, repairs, and installs wooden structures and furniture.',
    'hammer',
  ),
  painter(
    4,
    'Painter',
    'Applies paint and coatings to walls, ceilings, and surfaces.',
    'paintbrush',
  ),
  welder(
    14,
    'Welder/Metal Fitter',
    'Joins and repairs metal parts using welding or fitting techniques.',
    'wrench',
  ),
  tileInstaller(
    5,
    'Tile Installer',
    'Installs floor and wall tiles with precision and finishing.',
    'layout-grid',
  ),
  roofer(
    6,
    'Roofer',
    'Installs and repairs roofs using different materials.',
    'home',
  ),
  cabinetMaker(
    15,
    'Cabinet Maker',
    'Designs and builds cabinets, furniture, and wooden fixtures.',
    'hammer',
  ),
  doorOrWindowRepair(
    7,
    'Door/Windows Repair',
    'Repairs or replaces doors, windows, and hinges.',
    'layout-grid',
  ),
  applianceRepair(
    8,
    'Appliance Repair',
    'Fixes and maintains home appliances like fridges or washers.',
    'wrench',
  ),
  airconCleaning(
    9,
    'Aircon Cleaning',
    'Cleans and services air conditioning units.',
    'wind',
  ),
  pestControl(
    10,
    'Pest Control',
    'Eliminates pests like insects and rodents safely.',
    'bug',
  ),
  furnitureAssembly(
    11,
    'Furniture Assembly',
    'Assembles and installs flat-pack or modular furniture.',
    'hammer',
  ),
  curtainInstaller(
    12,
    'Curtain/Blinds Installer',
    'Installs curtains, blinds, and window coverings.',
    'layout-grid',
  ),
  locksmith(
    13,
    'Locksmith',
    'Installs, repairs, and opens locks for homes or vehicles.',
    'key',
  ),
  houseCleaning(
    14,
    'House Cleaning',
    'Performs regular household cleaning and tidying tasks.',
    'sparkles',
  ),
  deepCleaning(
    15,
    'Deep Cleaning',
    'Provides intensive cleaning for hard-to-reach or post-renovation areas.',
    'sparkles',
  ),
  laundry(
    17,
    'Laundry',
    'Washes, folds, and irons clothes and linens.',
    'shirt',
  ),
  windowCleaning(
    19,
    'Door/Window Cleaning',
    'Cleans glass doors and windows in homes or offices.',
    'sparkles',
  ),
  carWashHomeService(
    20,
    'Car Wash (Home Service)',
    'Provides car washing and detailing at the client’s home.',
    'car',
    hasTracker: true,
  ),
  organizer(
    21,
    'Organizer',
    'Helps declutter and organize storage or living spaces.',
    'package',
  ),
  garbageHauling(
    22,
    'Garbage Hauling',
    'Collects and disposes of waste and junk materials.',
    'truck',
  ),
  septicTankCleaning(
    25,
    'Septic Tank Cleaning',
    'Cleans and siphons septic tanks and drainage systems.',
    'droplets',
  ),
  gardener(
    23,
    'Gardener',
    'Maintains gardens, trims plants, and landscapes lawns.',
    'flower-2',
  ),
  grassCutting(
    24,
    'Grass Cutting / Mower',
    'Cuts and maintains lawns and grassy areas.',
    'flower-2',
  ),
  poolCleaning(
    26,
    'Pool Cleaning',
    'Cleans and maintains swimming pools.',
    'waves',
  ),
  carWash(
    30,
    'Car Wash',
    'Washes and details vehicles in a fixed location.',
    'car',
  ),
  tireReplacement(
    31,
    'Tire Replacement',
    'Provides tire change and repair services.',
    'settings',
  ),
  batteryJumpstart(
    32,
    'Battery Jumpstart',
    'Assists vehicles with dead batteries.',
    'zap',
  ),
  oilChange(
    33,
    'Oil Change',
    'Performs vehicle oil and filter replacements.',
    'droplets',
  ),
  mobileMechanic(
    34,
    'Mobile Mechanic',
    'Provides repair and diagnostics at the customer’s location.',
    'wrench',
  ),
  towing(
    35,
    'Towing',
    'Tows vehicles or provides roadside assistance.',
    'truck',
  ),
  motorcycleTuneUp(
    36,
    'Motorcycle Tune Up',
    'Performs maintenance and tune-ups for motorcycles.',
    'settings',
  ),
  personalShopper(
    37,
    'Personal Shopper',
    'Shops for groceries, clothes, or items for clients.',
    'package',
    hasTracker: true,
  ),
  groceryDelivery(
    38,
    'Grocery Delivery',
    'Delivers grocery orders to customers.',
    'package',
    hasTracker: true,
  ),
  parcelDelivery(
    39,
    'Parcel Delivery',
    'Delivers packages and small parcels door-to-door.',
    'package',
    hasTracker: true,
  ),
  documentRunner(
    40,
    'Document Runner',
    'Handles document pick-up and delivery tasks.',
    'file-text',
    hasTracker: true,
  ),
  foodDelivery(
    41,
    'Food Delivery',
    'Delivers meals or beverages from restaurants.',
    'utensils',
    hasTracker: true,
  ),
  prescriptionPickup(
    42,
    'Prescription Pickup',
    'Picks up and delivers medicines for clients.',
    'activity',
  ),
  queueingService(
    43,
    'Queueing Service',
    'Waits in line or processes tasks on behalf of clients.',
    'person-standing',
  ),
  laundryPickup(
    44,
    'Laundry Pickup',
    'Picks up and delivers laundry for washing.',
    'shirt',
    hasTracker: true,
  ),
  furnitureMoving(
    45,
    'Furniture Moving',
    'Moves and relocates furniture or appliances.',
    'truck',
  ),
  truckRental(
    46,
    'Truck Rental',
    'Provides truck rental for hauling and delivery.',
    'truck',
  ),
  packing(
    47,
    'Packing',
    'Packs items securely for transport or storage.',
    'package',
  ),
  storageOrganization(
    48,
    'Storage Organization',
    'Organizes and arranges storage spaces efficiently.',
    'package',
  ),
  furnitureDisposal(
    49,
    'Furniture Disposal',
    'Removes and disposes of old or unwanted furniture.',
    'truck',
  ),
  relocationService(
    84,
    'Relocation Service',
    'Provides end-to-end moving and relocation assistance.',
    'map',
  ),
  babysitter(
    50,
    'Baby Sitter',
    'Takes care of infants or children temporarily.',
    'heart',
  ),
  elderlyCare(
    51,
    'Elderly Care',
    'Provides personal care and assistance for elderly individuals.',
    'heart',
  ),
  petSitting(
    52,
    'Pet Sitter',
    'Cares for pets while the owner is away.',
    'heart',
  ),
  petGrooming(
    53,
    'Pet Grooming',
    'Bathes and grooms pets for hygiene and style.',
    'heart',
  ),
  houseSitter(
    54,
    'House Sitter',
    'Looks after a home while owners are away.',
    'house',
  ),
  tutor(
    55,
    'Tutor',
    'Provides private academic instruction or tutoring.',
    'book-open',
  ),
  personalAssistant(
    56,
    'Personal Assistant',
    'Helps with errands, scheduling, and personal tasks.',
    'user',
  ),
  computerRepair(
    57,
    'Computer Repair',
    'Repairs and maintains computers and laptops.',
    'monitor',
  ),
  smartphoneSetup(
    58,
    'Smart Phone Setup',
    'Sets up and configures smartphones.',
    'phone',
  ),
  wifiSetup(
    59,
    'WiFi Setup',
    'Installs and configures Wi-Fi routers and networks.',
    'zap',
  ),
  cctvSetup(
    60,
    'CCTV Setup',
    'Installs and maintains CCTV and security cameras.',
    'camera',
  ),
  smartHome(
    61,
    'Smart Home Setup',
    'Sets up smart devices like lights, locks, and sensors.',
    'house',
  ),
  printerSetup(
    62,
    'Printer Setup',
    'Installs and connects printers and scanners.',
    'monitor',
  ),
  photoEditing(
    63,
    'Photo Editing',
    'Edits and enhances digital photos.',
    'pen-tool',
  ),
  socialMediaHelp(
    64,
    'Social Media Help',
    'Assists with managing social media accounts.',
    'message-square',
  ),
  haircut(
    65,
    'haircut',
    'Provides haircut and hairstyling services.',
    'scissors',
  ),
  makeupArtist(
    66,
    'make-up artist',
    'Applies makeup for events or photoshoots.',
    'brush',
  ),
  massageTherapist(
    67,
    'massage therapist',
    'Provides body massage for relaxation or therapy.',
    'hand',
  ),
  nailTechnician(
    68,
    'nail technician',
    'Performs manicure, pedicure, and nail art.',
    'hand',
  ),
  personalTrainer(
    69,
    'personal trainer',
    'Guides fitness routines and workout programs.',
    'dumbbell',
  ),
  yogaInstructor(
    70,
    'yoga instructor',
    'Teaches yoga poses and mindfulness practices.',
    'brain',
  ),
  photographer(
    71,
    'photographer',
    'Captures and edits photos for personal or event use.',
    'camera',
  ),
  eventDecorator(
    72,
    'event decorator',
    'Designs and decorates event venues.',
    'party-popper',
  ),
  partyHelper(
    73,
    'party helper',
    'Assists in event setup, serving, and cleanup.',
    'party-popper',
  ),
  flyerDistribution(
    74,
    'flyer distribution',
    'Distributes flyers or promotional materials.',
    'archive',
  ),
  surveyTaker(
    75,
    'survey taker',
    'Conducts surveys or collects public feedback.',
    'square-split-vertical',
  ),
  posterInstallation(
    76,
    'poster installation',
    'Installs posters, banners, or signage.',
    'square-split-vertical',
  ),
  petPoopScooping(
    77,
    'pet poop scooping',
    'Cleans and disposes of pet waste.',
    'trash',
  ),
  waterDelivery(
    78,
    'water delivery',
    'Delivers drinking water to homes or offices.',
    'container',
  ),
  trashBinCleaning(
    79,
    'trash bin cleaning',
    'Cleans and sanitizes garbage bins.',
    'trash',
  ),
  balloonDecoration(
    80,
    'balloon decoration',
    'Creates balloon setups for parties or events.',
    'party-popper',
  ),
  seasonalHelper(
    81,
    'seasonal helper',
    'Provides help during holidays or special seasons.',
    'calendar',
  ),
  queueProxy(
    82,
    'queue proxy',
    'Waits in line or processes transactions for clients.',
    'square-split-vertical',
  ),
  eventHelper(
    83,
    'event helper',
    'Assists in managing and supporting events.',
    'party-popper',
  ),
  softwareDeveloper(
    200,
    'Software Developer',
    'Designs, builds, and maintains software applications and systems.',
    'code',
  ),
  mobileAppDeveloper(
    201,
    'Mobile App Developer',
    'Develops applications for Android and iOS platforms.',
    'phone',
  ),
  webDeveloper(
    202,
    'Web Developer',
    'Builds and maintains websites and web applications.',
    'code',
  ),
  uiUxDesigner(
    203,
    'UI/UX Designer',
    'Designs user interfaces and improves user experience.',
    'pen-tool',
  ),
  qualityAssuranceTester(
    204,
    'QA Tester',
    'Tests software to ensure quality and detect bugs.',
    'shield-check',
  ),
  devOpsEngineer(
    205,
    'DevOps Engineer',
    'Manages CI/CD pipelines, infrastructure, and deployments.',
    'settings',
  ),
  cloudSolutionsArchitect(
    206,
    'Cloud Solutions Architect',
    'Designs cloud-based architectures and solutions.',
    'hexagon',
  ),
  itSupportSpecialist(
    207,
    'IT Support Specialist',
    'Provides technical support and troubleshooting.',
    'monitor',
  ),
  dataAnalyst(
    208,
    'Data Analyst',
    'Analyzes data to extract insights and support decisions.',
    'calculator',
  ),
  cybersecurityAnalyst(
    209,
    'Cybersecurity Analyst',
    'Protects systems and data from cyber threats.',
    'shield',
  ),
  blockchainDeveloper(
    210,
    'Blockchain Developer',
    'Develops decentralized applications and blockchain systems.',
    'hexagon',
  ),
  smartContractAuditor(
    211,
    'Smart Contract Auditor',
    'Reviews and audits smart contracts for security.',
    'file-text',
  ),
  productManager(
    212,
    'Product Manager',
    'Oversees product planning, execution, and delivery.',
    'briefcase',
  ),
  uxResearcher(
    213,
    'UX Researcher',
    'Conducts research to improve product usability.',
    'search',
  ),
  accountant(
    214,
    'Accountant',
    'Manages financial records, reporting, and compliance.',
    'calculator',
  ),
  financialAnalyst(
    215,
    'Financial Analyst',
    'Analyzes financial data and investment opportunities.',
    'trending-up',
  ),
  taxSpecialist(
    216,
    'Tax Specialist',
    'Handles tax planning, filing, and compliance.',
    'file-text',
  ),
  businessAnalyst(
    217,
    'Business Analyst',
    'Analyzes business processes and requirements.',
    'trending-up',
  ),
  projectManager(
    218,
    'Project Manager',
    'Plans and manages projects from start to finish.',
    'briefcase',
  ),
  operationsManager(
    219,
    'Operations Manager',
    'Oversees daily business operations and efficiency.',
    'settings',
  ),
  procurementSpecialist(
    220,
    'Procurement Specialist',
    'Manages sourcing and purchasing of goods and services.',
    'package',
  ),
  riskComplianceOfficer(
    221,
    'Risk & Compliance Officer',
    'Ensures regulatory compliance and risk management.',
    'shield-check',
  ),
  hrGeneralist(
    222,
    'HR Generalist',
    'Handles general human resource functions.',
    'person-standing',
  ),
  hrManager(
    223,
    'HR Manager',
    'Leads and manages human resource operations.',
    'person-standing',
  ),
  recruitmentSpecialist(
    224,
    'Recruitment Specialist',
    'Sources, screens, and hires candidates.',
    'search',
  ),
  virtualAssistant(
    225,
    'Virtual Assistant',
    'Provides remote administrative and support services.',
    'user',
  ),
  graphicDesigner(
    226,
    'Graphic Designer',
    'Creates visual designs for digital and print media.',
    'palette',
  ),
  contentWriter(
    227,
    'Content Writer',
    'Writes content for blogs, websites, and marketing.',
    'file-text',
  ),
  copywriter(
    228,
    'Copywriter',
    'Writes persuasive marketing and advertising copy.',
    'pen-tool',
  ),
  videoEditor(
    229,
    'Video Editor',
    'Edits and produces video content.',
    'camera',
  ),
  animator(
    230,
    'Animator',
    'Creates animations for media and presentations.',
    'arrow-right',
  ),
  motionGraphicsArtist(
    231,
    'Motion Graphics Artist',
    'Designs animated graphics and visual effects.',
    'arrow-right',
  ),
  technicalWriter(
    232,
    'Technical Writer',
    'Creates documentation and technical guides.',
    'file-text',
  ),
  editor(233, 'Editor', 'Reviews and edits written or visual content.', 'pen'),
  proofreader(
    234,
    'Proofreader',
    'Checks content for grammar, spelling, and accuracy.',
    'check',
  ),
  digitalMarketingSpecialist(
    235,
    'Digital Marketing Specialist',
    'Plans and executes online marketing campaigns.',
    'trending-up',
  ),
  seoSpecialist(
    236,
    'SEO Specialist',
    'Optimizes websites for search engines.',
    'search',
  ),
  socialMediaManager(
    237,
    'Social Media Manager',
    'Manages social media content and engagement.',
    'message-square',
  ),
  brandManager(
    238,
    'Brand Manager',
    'Develops and maintains brand identity.',
    'star',
  ),
  salesExecutive(
    239,
    'Sales Executive',
    'Drives sales and manages client relationships.',
    'briefcase',
  ),
  businessDevelopmentManager(
    240,
    'Business Development Manager',
    'Identifies and grows business opportunities.',
    'trending-up',
  ),
  accountManager(
    241,
    'Account Manager',
    'Manages client accounts and partnerships.',
    'user',
  ),
  customerSuccessManager(
    242,
    'Customer Success Manager',
    'Ensures customer satisfaction and retention.',
    'heart',
  ),
  affiliateMarketingManager(
    243,
    'Affiliate Marketing Manager',
    'Manages affiliate marketing programs.',
    'arrow-right',
  ),
  emailMarketingSpecialist(
    244,
    'Email Marketing Specialist',
    'Creates and manages email marketing campaigns.',
    'mail',
  ),
  ecommerceSpecialist(
    245,
    'E-commerce Specialist',
    'Manages online stores and digital sales channels.',
    'package',
  ),
  lawyer(246, 'Lawyer', 'Provides legal advice and representation.', 'scale'),
  civilEngineer(
    247,
    'Civil Engineer',
    'Designs and oversees construction projects.',
    'building',
  ),
  architect(
    248,
    'Architect',
    'Plans and designs buildings and structures.',
    'layout-grid',
  ),
  surveyor(
    249,
    'Surveyor',
    'Measures and maps land and property boundaries.',
    'map-pin',
  ),
  onlineTutor(
    250,
    'Online Tutor',
    'Provides instruction via digital platforms.',
    'book-open',
  ),
  corporateTrainer(
    251,
    'Corporate Trainer',
    'Delivers professional development training.',
    'graduation-cap',
  ),
  musicTeacher(
    252,
    'Music Teacher',
    'Teaches musical instruments and theory.',
    'graduation-cap',
  ),
  languageTeacher(
    253,
    'Language Teacher',
    'Instructs students in new languages.',
    'globe',
  ),
  healthCoach(
    254,
    'Health Coach',
    'Guides clients towards healthy lifestyles.',
    'activity',
  ),
  physicalTherapist(
    255,
    'Physical Therapist',
    'Helps patients recover from physical injuries.',
    'stethoscope',
  ),
  nutritionist(
    256,
    'Nutritionist',
    'Provides expert advice on food and health.',
    'stethoscope',
  ),
  customerSupportRep(
    257,
    'Customer Support Rep',
    'Assists customers with inquiries and issues.',
    'headset',
  ),
  communityModerator(
    258,
    'Community Moderator',
    'Manages and monitors online communities.',
    'users',
  ),
  liveChatAgent(
    259,
    'Live Chat Agent',
    'Provides real-time support via chat.',
    'message-square',
  ),
  eventHelper_misc(
    260,
    'Event Helper',
    'Assists in event logistics and support.',
    'users',
  ),
  surveyTaker_misc(
    261,
    'Survey Taker',
    'Participates in data collection and surveys.',
    'file-text',
  ),
  foodServer(
    262,
    'Food Server',
    'Serves food and beverages at events.',
    'utensils',
  ),
  others(0, 'Others', 'Miscellaneous tasks not covered elsewhere.', 'package');

  final int id;
  final String label;
  final String description;
  final String icon;
  final bool hasTracker;

  const JobCategory(
    this.id,
    this.label,
    this.description,
    this.icon, {
    this.hasTracker = false,
  });

  bool get onSiteOnly {
    return switch (this) {
      JobCategory.electrician ||
      JobCategory.plumber ||
      JobCategory.mason ||
      JobCategory.carpenter ||
      JobCategory.painter ||
      JobCategory.welder ||
      JobCategory.tileInstaller ||
      JobCategory.roofer ||
      JobCategory.cabinetMaker ||
      JobCategory.doorOrWindowRepair ||
      JobCategory.applianceRepair ||
      JobCategory.airconCleaning ||
      JobCategory.pestControl ||
      JobCategory.furnitureAssembly ||
      JobCategory.curtainInstaller ||
      JobCategory.locksmith ||
      JobCategory.houseCleaning ||
      JobCategory.deepCleaning ||
      JobCategory.laundry ||
      JobCategory.windowCleaning ||
      JobCategory.carWashHomeService ||
      JobCategory.organizer ||
      JobCategory.garbageHauling ||
      JobCategory.septicTankCleaning ||
      JobCategory.gardener ||
      JobCategory.grassCutting ||
      JobCategory.poolCleaning ||
      JobCategory.carWash ||
      JobCategory.tireReplacement ||
      JobCategory.batteryJumpstart ||
      JobCategory.oilChange ||
      JobCategory.mobileMechanic ||
      JobCategory.towing ||
      JobCategory.motorcycleTuneUp ||
      JobCategory.personalShopper ||
      JobCategory.groceryDelivery ||
      JobCategory.parcelDelivery ||
      JobCategory.documentRunner ||
      JobCategory.foodDelivery ||
      JobCategory.prescriptionPickup ||
      JobCategory.queueingService ||
      JobCategory.laundryPickup ||
      JobCategory.furnitureMoving ||
      JobCategory.truckRental ||
      JobCategory.packing ||
      JobCategory.storageOrganization ||
      JobCategory.furnitureDisposal ||
      JobCategory.relocationService ||
      JobCategory.babysitter ||
      JobCategory.elderlyCare ||
      JobCategory.petSitting ||
      JobCategory.petGrooming ||
      JobCategory.houseSitter ||
      JobCategory.haircut ||
      JobCategory.makeupArtist ||
      JobCategory.massageTherapist ||
      JobCategory.nailTechnician ||
      JobCategory.personalTrainer ||
      JobCategory.photographer ||
      JobCategory.eventDecorator ||
      JobCategory.partyHelper ||
      JobCategory.flyerDistribution ||
      JobCategory.surveyTaker ||
      JobCategory.posterInstallation ||
      JobCategory.petPoopScooping ||
      JobCategory.waterDelivery ||
      JobCategory.trashBinCleaning ||
      JobCategory.balloonDecoration ||
      JobCategory.seasonalHelper ||
      JobCategory.queueProxy ||
      JobCategory.eventHelper ||
      JobCategory.eventHelper_misc ||
      JobCategory.foodServer ||
      JobCategory.surveyor => true,
      _ => false,
    };
  }
}

enum JobCategoryGroup {
  homeRepair(1, 'Home Repair & Maintenance', 'hammer', 'text-amber-600', [
    JobCategory.electrician,
    JobCategory.plumber,
    JobCategory.mason,
    JobCategory.carpenter,
    JobCategory.painter,
    JobCategory.welder,
    JobCategory.tileInstaller,
    JobCategory.roofer,
    JobCategory.cabinetMaker,
    JobCategory.doorOrWindowRepair,
    JobCategory.applianceRepair,
    JobCategory.airconCleaning,
    JobCategory.pestControl,
    JobCategory.furnitureAssembly,
    JobCategory.curtainInstaller,
    JobCategory.locksmith,
  ]),
  cleaning(2, 'Cleaning & Organizing', 'sparkles', 'text-indigo-500', [
    JobCategory.houseCleaning,
    JobCategory.deepCleaning,
    JobCategory.laundry,
    JobCategory.windowCleaning,
    JobCategory.carWashHomeService,
    JobCategory.organizer,
    JobCategory.garbageHauling,
    JobCategory.septicTankCleaning,
  ]),
  outdoor(3, 'Outdoor & Garden', 'flower-2', 'text-green-600', [
    JobCategory.gardener,
    JobCategory.grassCutting,
    JobCategory.poolCleaning,
  ]),
  automotive(4, 'Automotive', 'wrench', 'text-sky-500', [
    JobCategory.carWash,
    JobCategory.tireReplacement,
    JobCategory.batteryJumpstart,
    JobCategory.oilChange,
    JobCategory.mobileMechanic,
    JobCategory.towing,
    JobCategory.motorcycleTuneUp,
  ]),
  delivery(5, 'Delivery & Errands', 'package', 'text-orange-500', [
    JobCategory.personalShopper,
    JobCategory.groceryDelivery,
    JobCategory.parcelDelivery,
    JobCategory.documentRunner,
    JobCategory.foodDelivery,
    JobCategory.prescriptionPickup,
    JobCategory.queueingService,
    JobCategory.laundryPickup,
  ]),
  moving(6, 'Moving & Logistics', 'truck', 'text-blue-600', [
    JobCategory.furnitureMoving,
    JobCategory.truckRental,
    JobCategory.packing,
    JobCategory.storageOrganization,
    JobCategory.furnitureDisposal,
    JobCategory.relocationService,
  ]),
  personalCare(7, 'Personal Care & Assistance', 'heart', 'text-pink-500', [
    JobCategory.babysitter,
    JobCategory.elderlyCare,
    JobCategory.petSitting,
    JobCategory.petGrooming,
    JobCategory.houseSitter,
    JobCategory.tutor,
    JobCategory.personalAssistant,
  ]),
  tech(8, 'Tech & IT Support', 'monitor', 'text-blue-500', [
    JobCategory.computerRepair,
    JobCategory.smartphoneSetup,
    JobCategory.wifiSetup,
    JobCategory.cctvSetup,
    JobCategory.smartHome,
    JobCategory.printerSetup,
    JobCategory.photoEditing,
    JobCategory.socialMediaHelp,
    JobCategory.softwareDeveloper,
    JobCategory.mobileAppDeveloper,
    JobCategory.webDeveloper,
    JobCategory.uiUxDesigner,
    JobCategory.qualityAssuranceTester,
    JobCategory.devOpsEngineer,
    JobCategory.cloudSolutionsArchitect,
    JobCategory.itSupportSpecialist,
    JobCategory.dataAnalyst,
    JobCategory.cybersecurityAnalyst,
    JobCategory.blockchainDeveloper,
    JobCategory.smartContractAuditor,
    JobCategory.productManager,
    JobCategory.uxResearcher,
  ]),
  business(9, 'Business, Finance & Admin', 'trending-up', 'text-emerald-600', [
    JobCategory.accountant,
    JobCategory.financialAnalyst,
    JobCategory.taxSpecialist,
    JobCategory.businessAnalyst,
    JobCategory.projectManager,
    JobCategory.operationsManager,
    JobCategory.procurementSpecialist,
    JobCategory.riskComplianceOfficer,
    JobCategory.hrGeneralist,
    JobCategory.hrManager,
    JobCategory.recruitmentSpecialist,
    JobCategory.virtualAssistant,
  ]),
  creative(10, 'Creative & Media', 'palette', 'text-purple-500', [
    JobCategory.graphicDesigner,
    JobCategory.contentWriter,
    JobCategory.copywriter,
    JobCategory.videoEditor,
    JobCategory.animator,
    JobCategory.motionGraphicsArtist,
    JobCategory.technicalWriter,
    JobCategory.editor,
    JobCategory.proofreader,
  ]),
  marketing(11, 'Marketing & Sales', 'trending-up', 'text-rose-500', [
    JobCategory.digitalMarketingSpecialist,
    JobCategory.seoSpecialist,
    JobCategory.socialMediaManager,
    JobCategory.brandManager,
    JobCategory.salesExecutive,
    JobCategory.businessDevelopmentManager,
    JobCategory.accountManager,
    JobCategory.customerSuccessManager,
    JobCategory.affiliateMarketingManager,
    JobCategory.emailMarketingSpecialist,
    JobCategory.ecommerceSpecialist,
  ]),
  professional(
    12,
    'Legal, Engineering & Pro Services',
    'scale',
    'text-zinc-700',
    [
      JobCategory.lawyer,
      JobCategory.civilEngineer,
      JobCategory.architect,
      JobCategory.surveyor,
    ],
  ),
  education(13, 'Education & Training', 'graduation-cap', 'text-amber-500', [
    JobCategory.onlineTutor,
    JobCategory.corporateTrainer,
    JobCategory.musicTeacher,
    JobCategory.languageTeacher,
  ]),
  health(14, 'Health & Wellness', 'stethoscope', 'text-red-500', [
    JobCategory.healthCoach,
    JobCategory.physicalTherapist,
    JobCategory.personalTrainer,
    JobCategory.nutritionist,
  ]),
  support(15, 'Customer Support', 'headset', 'text-blue-500', [
    JobCategory.customerSupportRep,
    JobCategory.communityModerator,
    JobCategory.liveChatAgent,
  ]),
  miscellaneousEvents(
    16,
    'Miscellaneous & Events',
    'package',
    'text-zinc-500',
    [
      JobCategory.eventHelper_misc,
      JobCategory.surveyTaker_misc,
      JobCategory.foodServer,
      JobCategory.others,
    ],
  );

  final int id;
  final String label;
  final String icon;
  final String color;
  final List<JobCategory> categories;

  const JobCategoryGroup(
    this.id,
    this.label,
    this.icon,
    this.color,
    this.categories,
  );
}

enum VehicleType {
  car,
  motorcycle,
  truck,
  suv,
  van;

  String get label => name[0].toUpperCase() + name.substring(1);
  String get icon => switch (this) {
    car => 'car',
    motorcycle => 'bike',
    truck => 'truck',
    suv => 'shield',
    van => 'truck',
  };
}

