// Contract drafts for Tranyx Vehicle Rentals

import 'package:shared/shared.dart';

String buildDefaultTranyxContract(VehicleRental rental) {
  final brandStr = rental.brand.isNotEmpty ? rental.brand : '[Vehicle Brand]';
  final modelStr = rental.model.isNotEmpty ? rental.model : '[Vehicle Model]';
  final yearStr = rental.year > 0 ? '${rental.year}' : '[Vehicle Year]';
  final plateStr = rental.plateNumber.isNotEmpty ? rental.plateNumber : '[Plate Number]';
  final valueStr = rental.vehicleValue > 0 ? '${rental.vehicleValue} TYXBIT' : '[Vehicle Value]';

  return '''
==================================================================
TRANYX PEER-TO-PEER VEHICLE RENTAL AGREEMENT
==================================================================

1. PARTIES
This Peer-to-Peer Vehicle Rental Agreement ("Agreement") is entered into by and between:
- Host/Owner (Lessor): ${rental.hostName} [${PartyVerificationHelper.formatIdentityStatusLabel(isVerified: rental.hostIsVerified, status: rental.hostVerificationStatus, explicitTier: rental.hostVerificationTier)}]
- Rentee/Renter (Lessee): ${rental.renteeName ?? '[Renter Full Name]'} [${PartyVerificationHelper.formatIdentityStatusLabel(isVerified: rental.renteeIsVerified, status: rental.renteeVerificationStatus, explicitTier: rental.renteeVerificationTier)}]
- Platform/Bridge: Tranyx Technology Inc. ("Tranyx" or "Platform")

2. VEHICLE SPECIFICATIONS
The Owner agrees to rent to the Renter the following vehicle:
- Brand/Manufacturer: $brandStr
- Model/Series: $modelStr
- Production Year: $yearStr
- Plate Number: $plateStr
- Insured Market Value: $valueStr
- Fuel Type: ${rental.fuelType ?? 'Gasoline'}
- Transmission: ${rental.transmission ?? 'Automatic'}

3. LTO REGISTRATION & COMPLIANCE
The Owner represents and warrants that:
- LTO Certificate of Registration (CR) Number: ${rental.ltoCrNumber}
- LTO Official Receipt (OR) Number: ${rental.ltoOrNumber}
- The vehicle is legally registered, in roadworthy condition, and clear of any police or traffic warrants.

4. PLATFORM ROLE AND LIMITATION OF LIABILITY
Owner and Renter explicitly acknowledge and agree that:
- TRANYX IS NOT AN OWNER, OPERATOR, OR INSURER OF VEHICLES LISTED ON THE MARKETPLACE.
- TRANYX ACTS SOLELY AS A PEER-TO-PEER BRIDGING PLATFORM AND CRYPTOGRAPHIC ESCROW MANAGER.
- IN NO EVENT SHALL TRANYX, ITS PARENT COMPANY, OFFICERS, EMPLOYEES, OR AGENTS BE LIABLE FOR ANY CLAIMS, DAMAGES, ACCIDENTS, INJURIES, THEFT, VANDALISM, TRAFFIC TICKETS, OR LITIGATION ARISING FROM THE USE OF THE VEHICLE.
- OWNER AND RENTER HEREBY COMPLETELY RELEASE AND HOLD TRANYX HARMLESS FROM ALL PLATFORM COMPROMISES OR OPERATIONAL ACTIONS.

5. RENTAL RATES & DURATION
- Package Option: ${rental.rentalDurationType?.toUpperCase() ?? '[Duration Type]'}
- Duration/Multiplier: ${rental.rentalMultiplier ?? '[Multiplier]'}
- Price per Unit: ${rental.priceDaily} TYXBIT (Daily Base Reference)
- Estimated Escrow Total: ${rental.totalCost ?? '[Total Cost]'} TYXBIT
- Hourly Extension Rate: ${rental.extensionRatePerHour} TYXBIT/Hour
- Late Return Penalty Rate: ${rental.latePenaltyRatePerHour} TYXBIT/Hour (Charged if returning past the agreed date/time)

6. INSURANCE POLICY
- Comprehensive Insurance Provider: ${rental.insuranceProvider}
- Policy Reference Number: ${rental.insurancePolicyNumber}
- Deductibles and third-party liabilities shall be borne fully by the Renter in the event of an at-fault accident.

7. COVENANTS AND USAGE RULES
The Renter agrees to:
- Operate the vehicle in accordance with all local road safety laws.
- Keep the vehicle free of contraband, narcotics, and dangerous materials.
- Return the vehicle with the same fuel level as received.
- Bear all costs for tollways, traffic tickets, parking fees, and impoundments incurred during the rental.

8. DIGITAL SIGNATURES & EXECUTION
By ticking the agreement checkbox and typing their full legal name below, the Renter executes this contract electronically.

Renter Signature: ${rental.renteeSignatureName ?? '[Digital Signature Name]'}
Renter Driver's License: ${rental.renteeLicenseNumber ?? '[License Number]'}
Signed At (Epoch Timestamp): ${rental.signedAt != null ? rental.signedAt!.toIso8601String() : '[Timestamp]'}
''';
}

String buildDefaultPropertyContract(PropertyRental rental) {
  final typeStr = rental.type.label;
  final catStr = rental.category.label;

  return '''
==================================================================
TRANYX PEER-TO-PEER PROPERTY LEASE AGREEMENT
==================================================================

1. PARTIES
This Peer-to-Peer Property Lease Agreement ("Agreement") is entered into by and between:
- Lessor/Property Owner: ${rental.hostName} [${PartyVerificationHelper.formatIdentityStatusLabel(isVerified: rental.hostIsVerified, status: rental.hostVerificationStatus, explicitTier: rental.hostVerificationTier)}]
- Lessee/Tenant: ${rental.renteeName ?? '[Tenant Full Name]'} [${PartyVerificationHelper.formatIdentityStatusLabel(isVerified: rental.renteeIsVerified, status: rental.renteeVerificationStatus, explicitTier: rental.renteeVerificationTier)}]
- Platform/Bridge: Tranyx Technology Inc. ("Tranyx" or "Platform")

2. PROPERTY SPECIFICATIONS
The Owner agrees to lease to the Tenant the following property:
- Property Title: ${rental.title}
- Property Category: $catStr
- Property Type: $typeStr
- Complete Address: ${rental.address}
- Amenities Included: ${rental.amenities.isEmpty ? 'None' : rental.amenities.join(', ')}

3. PLATFORM ROLE AND LIMITATION OF LIABILITY
Owner and Tenant explicitly acknowledge and agree that:
- TRANYX IS NOT A REAL ESTATE AGENT, PROPERTY MANAGER, OR BROKER.
- TRANYX ACTS SOLELY AS A PEER-TO-PEER BRIDGING PLATFORM AND CRYPTOGRAPHIC ESCROW MANAGER.
- IN NO EVENT SHALL TRANYX, ITS PARENT COMPANY, OFFICERS, EMPLOYEES, OR AGENTS BE LIABLE FOR ANY CLAIMS, DAMAGES, PROPERTY ACCIDENTS, INJURIES, THEFT, VANDALISM, FIRE, OR LITIGATION ARISING FROM THE USE OF THE PROPERTY.
- OWNER AND TENANT HEREBY COMPLETELY RELEASE AND HOLD TRANYX HARMLESS FROM ALL OPERATIONAL ACTIONS.

4. LEASE RATES & PAYMENT ESCROW
- Monthly Rental Rate: ${rental.priceMonthly} TYXBIT
- Security Deposit: ${rental.depositMonths} Month(s) (${rental.priceMonthly * rental.depositMonths} TYXBIT)
- Estimated Escrow Total: ${rental.totalCost ?? '[Total Cost]'} TYXBIT
- Lease Term: ${rental.rentalMultiplier ?? '[Multiplier]'} ${rental.rentalDurationType ?? 'month(s)'}

5. COVENANTS AND HOUSE RULES
The Tenant agrees to:
- Maintain the property in good, clean condition.
- Use the property only for legal activities. Illegal substances or commercial activities in residential areas are strictly prohibited.
- Pay all utility bills (electricity, water, internet) if not explicitly included in the rent.
- Vacate the premises peacefully at the end of the lease unless renewed.

6. DIGITAL SIGNATURES & EXECUTION
By ticking the agreement checkbox and signing below, the Tenant executes this lease contract.

Tenant Signature: ${rental.renteeSignatureName ?? '[Digital Signature Name]'}
Tenant Identification: ${rental.renteeLicenseNumber ?? '[ID / Reference Number]'}
Signed At (Timestamp): ${rental.signedAt != null ? rental.signedAt!.toIso8601String() : '[Timestamp]'}
''';
}
