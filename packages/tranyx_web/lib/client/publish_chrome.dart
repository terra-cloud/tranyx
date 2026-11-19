/// The floating mobile bar and the Nyx button cover a full-width Publish control.
/// Hide them while a create/post form is open. Services use the job composer.
bool hideMobileChromeForPublish({
  required bool jobTracking,
  required bool creatingJob,
  required bool listingVehicle,
  required bool listingProperty,
  required bool editingVehicle,
  required bool editingProperty,
}) {
  return jobTracking || creatingJob || listingVehicle || listingProperty || editingVehicle || editingProperty;
}
