import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../../components/ui_helpers.dart';

class ContractViewerComponent extends StatelessComponent {
  final VehicleRental? vehicleRental;
  final PropertyRental? propertyRental;
  final String? customTerms;
  final String? contractType;

  const ContractViewerComponent({
    this.vehicleRental,
    this.propertyRental,
    this.customTerms,
    this.contractType,
    super.key,
  });

  bool get _isDarkTheme => true;

  @override
  Component build(BuildContext context) {
    // Determine mode
    final isCustom = (contractType == 'Custom Contract') ||
        (customTerms != null &&
            customTerms!.isNotEmpty &&
            customTerms != 'Standard P2P terms' &&
            customTerms != 'Standard P2P Lease terms' &&
            customTerms != 'Standard P2P lease' &&
            contractType != 'Tranyx Standard' &&
            contractType != 'Standard');
    final isDark = _isDarkTheme; // Use app's dark theme styling conventions
    final bgBorderText = isDark
        ? "bg-zinc-950 border-zinc-800 text-zinc-300"
        : "bg-white border-zinc-200 text-zinc-800 shadow-inner";

    return div(
      classes: 'w-full rounded-2xl border p-6 md:p-8 font-sans leading-relaxed text-left overflow-y-auto max-h-[480px] $bgBorderText',
      [
        if (isCustom)
          ..._buildCustomContract(isDark)
        else if (vehicleRental != null)
          ..._buildVehicleContract(vehicleRental!, isDark)
        else if (propertyRental != null)
          ..._buildPropertyContract(propertyRental!, isDark)
        else
          div([Component.text('No contract details available.')])
      ],
    );
  }

  // ── CUSTOM CONTRACTS PREVIEW ──────────────────────────────────────────────
  List<Component> _buildCustomContract(bool isDark) {
    final terms = customTerms ?? 'No custom contract terms provided.';
    return [
      div(classes: 'flex flex-col items-center text-center mb-6', [
        div(classes: 'p-3 rounded-full bg-amber-500/10 text-amber-400 mb-3', [
          lIcon('file-text', cls: 'w-8 h-8'),
        ]),
        h2(classes: 'text-lg font-black tracking-tight ${isDark ? "text-white" : "text-zinc-900"}', [
          Component.text('CUSTOM LEASE & RENTAL AGREEMENT'),
        ]),
        p(classes: 'text-xs text-zinc-500 mt-1', [
          Component.text('Underwritten and defined by the listing host'),
        ]),
      ]),

      div(classes: 'border-t border-b ${isDark ? "border-zinc-800" : "border-zinc-200"} py-4 my-4', [
        p(classes: 'text-xs text-zinc-400 font-bold mb-2 uppercase tracking-wide', [
          Component.text('Contract Terms & Conditions'),
        ]),
        div(
          classes: 'whitespace-pre-wrap text-sm leading-relaxed ${isDark ? "text-zinc-300" : "text-zinc-700"}',
          [Component.text(terms)],
        ),
      ]),

      _buildSafetyNotice(isDark),
    ];
  }

  // ── VEHICLE RENTAL STANDARD CONTRACT ──────────────────────────────────────
  List<Component> _buildVehicleContract(VehicleRental r, bool isDark) {
    final brand = r.brand.isNotEmpty ? r.brand : '[Vehicle Brand]';
    final model = r.model.isNotEmpty ? r.model : '[Vehicle Model]';
    final year = r.year > 0 ? '${r.year}' : '[Vehicle Year]';
    final plate = r.plateNumber.isNotEmpty ? r.plateNumber : '[Plate Number]';
    final value = r.vehicleValue > 0 ? '${r.vehicleValue} TYXBIT' : '[Vehicle Value]';

    return [
      // Document Header
      _buildDocHeader(
        isDark: isDark,
        title: 'PEER-TO-PEER VEHICLE RENTAL AGREEMENT',
        sub: 'Tranyx Smart Escrow Framework • Standard P2P Form',
      ),

      // Section 1: Parties
      _buildSectionHeader('1. PARTIES TO THE AGREEMENT', isDark),
      div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4 mb-6', [
        _buildPartyCard(
          role: 'OWNER / HOST',
          name: r.hostName,
          license: 'Verified Account',
          photoUrl: r.hostPhotoUrl,
          isDark: isDark,
        ),
        _buildPartyCard(
          role: 'RENTER / LESSEE',
          name: r.renteeName ?? '[Renter Full Name]',
          license: r.renteeLicenseNumber != null ? 'License: ${r.renteeLicenseNumber}' : '[License Pending Signature]',
          photoUrl: r.renteePhotoUrl,
          isDark: isDark,
        ),
      ]),

      // Section 2: Specs
      _buildSectionHeader('2. VEHICLE SPECIFICATIONS', isDark),
      _buildSpecsGrid(isDark, [
        _specRow('Brand/Make', brand),
        _specRow('Model/Series', model),
        _specRow('Production Year', year),
        _specRow('Plate/MV File No.', plate),
        _specRow('Insured Value', value),
        _specRow('Fuel Type', r.fuelType ?? 'Gasoline'),
        _specRow('Transmission', r.transmission ?? 'Automatic'),
      ]),

      // Section 3: LTO Compliance
      _buildSectionHeader('3. LTO REGISTRATION & COMPLIANCE', isDark),
      p(classes: 'text-sm mb-4 leading-relaxed', [
        Component.text('The Owner warrants that the vehicle is legally registered, roadworthy, and free of any police/traffic warrants:'),
      ]),
      _buildSpecsGrid(isDark, [
        _specRow('LTO Certificate of Registration (CR)', r.ltoCrNumber.isNotEmpty ? r.ltoCrNumber : 'PENDING'),
        _specRow('LTO Official Receipt (OR)', r.ltoOrNumber.isNotEmpty ? r.ltoOrNumber : 'PENDING'),
        _specRow('Comprehensive Insurance', r.insuranceProvider.isNotEmpty ? r.insuranceProvider : 'N/A'),
        _specRow('Policy Reference No.', r.insurancePolicyNumber.isNotEmpty ? r.insurancePolicyNumber : 'N/A'),
      ]),

      // Section 4: Non-liability Notice
      _buildSectionHeader('4. PLATFORM ROLE & DISCLAIMER', isDark),
      _buildPlatformDisclaimer(isDark),

      // Section 5: Rates & Escrow
      _buildSectionHeader('5. RENTAL RATES & ESCROW PAYMENT', isDark),
      _buildSpecsGrid(isDark, [
        _specRow('Duration Package', r.rentalDurationType?.toUpperCase() ?? 'DAILY'),
        _specRow('Multiplier / Qty', r.rentalMultiplier != null ? '${r.rentalMultiplier} unit(s)' : '[Quantity]'),
        _specRow('Daily Base Reference', '₱${r.priceDaily} / day'),
        _specRow('Total Lock Escrow', r.totalCost != null ? '₱${r.totalCost}' : '[Total Cost Pending]'),
        _specRow('Extension Rate', '₱${r.extensionRatePerHour} / Hour'),
        _specRow('Late Penalty Fee', '₱${r.latePenaltyRatePerHour} / Hour'),
      ]),

      // Section 6: Covenants & Rules
      _buildSectionHeader('6. CONTRACT COVENANTS & GENERAL RULES', isDark),
      ul(classes: 'space-y-2 mb-6 text-sm text-zinc-400 list-none p-0 m-0', [
        _bulletRow('Renter must operate the vehicle in strict compliance with all local road safety laws.'),
        _bulletRow('Renter must keep the vehicle clear of any contrabands, narcotics, or hazardous materials.'),
        _bulletRow('Vehicle must be returned with the same fuel level as recorded during pickup.'),
        _bulletRow('Tollways, parking tickets, and traffic violations incurred during the period are borne by the Renter.'),
      ]),

      // Section 7: Signatures
      _buildSectionHeader('7. DIGITAL EXECUTION STAMPS', isDark),
      div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4 mt-2', [
        _buildSignatureStamp(
          title: 'Owner/Host Authorization',
          signedName: r.hostName,
          timestamp: r.createdAt.toString().substring(0, 16),
          isDark: isDark,
          isSigned: true,
        ),
        _buildSignatureStamp(
          title: 'Renter/Lessee Digital Sign',
          signedName: r.renteeSignatureName,
          timestamp: r.signedAt != null ? r.signedAt!.toIso8601String().substring(0, 16).replaceFirst('T', ' ') : null,
          isDark: isDark,
          isSigned: r.signedAt != null,
        ),
      ]),
    ];
  }

  // ── PROPERTY RENTAL STANDARD CONTRACT ─────────────────────────────────────
  List<Component> _buildPropertyContract(PropertyRental r, bool isDark) {
    final title = r.title.isNotEmpty ? r.title : '[Property Title]';
    final type = r.type.label;
    final cat = r.category.label;
    final address = r.address.isNotEmpty ? r.address : 'Default Site';

    return [
      // Document Header
      _buildDocHeader(
        isDark: isDark,
        title: 'PEER-TO-PEER PROPERTY LEASE AGREEMENT',
        sub: 'Tranyx Smart Escrow Framework • P2P Tenancy Form',
      ),

      // Section 1: Parties
      _buildSectionHeader('1. PARTIES TO THE AGREEMENT', isDark),
      div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4 mb-6', [
        _buildPartyCard(
          role: 'LESSOR / PROPERTY OWNER',
          name: r.hostName,
          license: 'Verified Landlord',
          photoUrl: r.hostPhotoUrl,
          isDark: isDark,
        ),
        _buildPartyCard(
          role: 'LESSEE / TENANT',
          name: r.renteeName ?? '[Tenant Full Name]',
          license: r.renteeLicenseNumber != null ? 'Government ID: ${r.renteeLicenseNumber}' : '[ID Pending Signature]',
          photoUrl: r.renteePhotoUrl,
          isDark: isDark,
        ),
      ]),

      // Section 2: Specs
      _buildSectionHeader('2. PROPERTY SPECIFICATIONS', isDark),
      _buildSpecsGrid(isDark, [
        _specRow('Property Title', title),
        _specRow('Category', cat),
        _specRow('Property Type', type),
        _specRow('Complete Address', address),
        _specRow('Amenities', r.amenities.isEmpty ? 'None' : r.amenities.join(', ')),
      ]),

      // Section 3: Non-liability Notice
      _buildSectionHeader('3. PLATFORM ROLE & DISCLAIMER', isDark),
      _buildPlatformDisclaimer(isDark),

      // Section 4: Lease Rates & Payments
      _buildSectionHeader('4. RENTAL ESCROW RATES & DEPOSITS', isDark),
      _buildSpecsGrid(isDark, [
        _specRow('Monthly Rental Rate', '₱${r.priceMonthly} / month'),
        _specRow('Security Deposit', r.depositMonths > 0 ? '${r.depositMonths} Month(s) (₱${r.priceMonthly * r.depositMonths})' : 'No Deposit Required'),
        _specRow('Lease Duration', r.rentalMultiplier != null ? '${r.rentalMultiplier} ${r.rentalDurationType ?? "month(s)"}' : '[Duration Pending]'),
        _specRow('Escrow Total Price', r.totalCost != null ? '₱${r.totalCost}' : '[Total Escrow Pending]'),
      ]),

      // Section 5: Covenants & Rules
      _buildSectionHeader('5. LEASE COVENANTS & HOUSE RULES', isDark),
      ul(classes: 'space-y-2 mb-6 text-sm text-zinc-400 list-none p-0 m-0', [
        _bulletRow('Tenant agrees to maintain the property in a clean, hygienic, and undamaged condition.'),
        _bulletRow('Use of the property is restricted to legal activities. No illegal substances or commercial operation in residential zones.'),
        _bulletRow('Tenant is responsible for utility bills (electricity, water, internet) unless explicitly covered in custom terms.'),
        _bulletRow('Lessor reserves the right to inspect premises with a 24-hour advance notice to Tenant.'),
      ]),

      // Section 6: Signatures
      _buildSectionHeader('6. DIGITAL EXECUTION STAMPS', isDark),
      div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4 mt-2', [
        _buildSignatureStamp(
          title: 'Lessor/Owner Authorization',
          signedName: r.hostName,
          timestamp: r.createdAt.toString().substring(0, 16),
          isDark: isDark,
          isSigned: true,
        ),
        _buildSignatureStamp(
          title: 'Lessee/Tenant Digital Sign',
          signedName: r.renteeSignatureName,
          timestamp: r.signedAt != null ? r.signedAt!.toIso8601String().substring(0, 16).replaceFirst('T', ' ') : null,
          isDark: isDark,
          isSigned: r.signedAt != null,
        ),
      ]),
    ];
  }

  // ── REUSABLE DESIGN SYSTEMS ───────────────────────────────────────────────

  Component _buildDocHeader({required bool isDark, required String title, required String sub}) {
    return div(classes: 'flex flex-col items-center text-center pb-6 mb-6 border-b ${isDark ? "border-zinc-800" : "border-zinc-150"}', [
      div(classes: 'px-3 py-1 rounded-full text-[10px] font-extrabold uppercase tracking-wider mb-3 flex items-center gap-1.5 '
          '${isDark ? "bg-purple-500/10 text-purple-400" : "bg-purple-50 text-purple-650"}', [
        lIcon('shield-check', cls: 'w-3.5 h-3.5'),
        Component.text('Tranyx Secure Escrow Contract'),
      ]),
      h1(classes: 'text-lg md:text-xl font-black tracking-tight ${isDark ? "text-white" : "text-zinc-900"}', [
        Component.text(title),
      ]),
      p(classes: 'text-xs text-zinc-500 mt-1', [Component.text(sub)]),
    ]);
  }

  Component _buildSectionHeader(String title, bool isDark) {
    return h3(classes: 'text-xs font-bold uppercase tracking-wider mb-3 mt-6 pb-1 border-b '
        '${isDark ? "text-purple-400 border-zinc-900" : "text-purple-650 border-zinc-100"}', [
      Component.text(title),
    ]);
  }

  Component _buildPartyCard({
    required String role,
    required String name,
    required String license,
    required String? photoUrl,
    required bool isDark,
  }) {
    final showPhoto = photoUrl != null && photoUrl.isNotEmpty && photoUrl != 'null';
    return div(
      classes: 'p-4 rounded-xl border flex items-center gap-3 '
          '${isDark ? "bg-zinc-900/40 border-zinc-805" : "bg-zinc-50 border-zinc-200"}',
      [
        div(
          classes: 'w-10 h-10 rounded-full flex-shrink-0 flex items-center justify-center overflow-hidden '
              '${isDark ? "bg-zinc-800" : "bg-zinc-200"}',
          [
            if (showPhoto)
              img(src: photoUrl, classes: 'w-full h-full object-cover')
            else
              lIcon('user', cls: 'w-5 h-5 text-zinc-500'),
          ],
        ),
        div([
          p(classes: 'text-[10px] font-bold text-zinc-550 uppercase tracking-wide', [Component.text(role)]),
          p(classes: 'text-sm font-bold ${isDark ? "text-white" : "text-zinc-900"}', [Component.text(name)]),
          p(classes: 'text-xs text-zinc-500 mt-0.5', [Component.text(license)]),
        ]),
      ],
    );
  }

  Component _buildSpecsGrid(bool isDark, List<Component> children) {
    return div(
      classes: 'rounded-xl border overflow-hidden mb-4 divide-y '
          '${isDark ? "border-zinc-850 bg-zinc-900/10 divide-zinc-850" : "border-zinc-150 bg-zinc-50/10 divide-zinc-150"}',
      children,
    );
  }

  Component _specRow(String key, String value) {
    return div(classes: 'grid grid-cols-3 p-3 text-xs', [
      span(classes: 'font-semibold text-zinc-500 col-span-1', [Component.text(key)]),
      span(classes: 'font-bold text-zinc-350 col-span-2 text-right md:text-left', [Component.text(value)]),
    ]);
  }

  Component _buildPlatformDisclaimer(bool isDark) {
    return div(
      classes: 'p-4 rounded-xl border flex items-start gap-3 '
          '${isDark ? "bg-blue-500/5 border-blue-500/10 text-blue-400" : "bg-blue-50 border-blue-100 text-blue-800"}',
      [
        lIcon('info', cls: 'w-5 h-5 flex-shrink-0 mt-0.5'),
        div(classes: 'text-xs leading-relaxed', [
          p(classes: 'font-bold mb-1', [Component.text('Lessor & Lessee Platform Agreement:')]),
          Component.text(
            'Tranyx operates solely as a peer-to-peer matching and cryptographic smart escrow release platform. '
            'The platform does not operate, manage, or insure vehicles/properties, and holds zero liability for claims, accidents, damages, or disputes arising from this contract.',
          ),
        ]),
      ],
    );
  }

  Component _buildSafetyNotice(bool isDark) {
    return div(
      classes: 'p-4 rounded-xl border flex items-start gap-3 '
          '${isDark ? "bg-amber-500/5 border-amber-500/10 text-amber-400" : "bg-amber-50 border-amber-100 text-amber-800"}',
      [
        lIcon('alert-triangle', cls: 'w-5 h-5 flex-shrink-0 mt-0.5'),
        div(classes: 'text-xs leading-relaxed', [
          p(classes: 'font-bold mb-1', [Component.text('Custom Contract Disclaimer:')]),
          Component.text(
            'This listing uses custom host-provided terms. Rentees should read this document carefully before signing. '
            'By signing and submitting the escrow payment, you agree to comply with the terms above.',
          ),
        ]),
      ],
    );
  }

  Component _bulletRow(String text) {
    return li(classes: 'flex items-start gap-2.5 text-xs text-zinc-400 leading-relaxed', [
      span(classes: 'text-purple-400 mt-1', [Component.text('•')]),
      span([Component.text(text)]),
    ]);
  }

  Component _buildSignatureStamp({
    required String title,
    required String? signedName,
    required String? timestamp,
    required bool isDark,
    required bool isSigned,
  }) {
    return div(
      classes: 'p-4 rounded-xl border flex flex-col items-center text-center justify-center min-h-[100px] relative overflow-hidden '
          '${isSigned ? (isDark ? "bg-green-500/5 border-green-500/20" : "bg-green-50 border-green-200") : (isDark ? "bg-zinc-900/30 border-dashed border-zinc-800" : "bg-zinc-50 border-dashed border-zinc-200")}',
      [
        p(classes: 'text-[10px] font-bold text-zinc-500 uppercase tracking-wider mb-2', [Component.text(title)]),
        if (isSigned && signedName != null) ...[
          if (signedName.startsWith('data:image/'))
            img(
              src: signedName,
              classes: 'max-h-12 w-auto object-contain bg-white rounded p-1 mb-2 max-w-[150px]',
              attributes: {'alt': 'Digital Stamp'},
            )
          else
            span(
              classes: 'text-base font-black italic tracking-wide text-green-400 my-1 font-serif',
              [Component.text(signedName)],
            ),
          p(classes: 'text-[9px] text-zinc-500', [Component.text('Timestamp: ${timestamp ?? "N/A"}')]),
          div(classes: 'absolute top-1 right-1 p-0.5 rounded-full bg-green-500/20 text-green-400 flex items-center justify-center', [
            lIcon('check', cls: 'w-3 h-3'),
          ]),
        ] else ...[
          lIcon('pen-tool', cls: 'w-5 h-5 text-zinc-600 mb-1'),
          p(classes: 'text-xs text-zinc-550 italic', [Component.text('Signature Required')]),
        ],
      ],
    );
  }
}
