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
- Host/Owner: ${rental.hostName} ("Owner")
- Rentee/Renter: ${rental.renteeName ?? '[Renter Full Name]'} ("Renter")
- Platform/Bridge: Tranyx Technology Inc. ("Tranyx" or "Platform")

2. VEHICLE SPECIFICATIONS
The Owner agrees to rent to the Renter the following vehicle:
- Brand/Manufacturer: $brandStr
- Model/Series: $modelStr
- Production Year: $yearStr
- Plate Number: $plateStr
- Insured Market Value: $valueStr

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
