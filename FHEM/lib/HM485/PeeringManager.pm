package HM485::PeeringManager;

use strict;
use warnings;
use POSIX qw(ceil);

use Data::Dumper;

=head2 getPeeringFromDevice
	Get config from Device
	
	@param	hash
	@param	int   the channel number
	

	@return	hash
=cut
sub getPeeringFromDevice($$) {
	my ($hash, $chNr) = @_;
	
	my $retVal = {};
	if ($chNr eq '0') {
		return;
	}
	my $peeringHash = getPeeringSettings($hash);
	
	if (ref($peeringHash) eq 'HASH' && exists ($peeringHash->{'peer_param'})) {
		my $addressStart = $peeringHash->{'address_start'} ? $peeringHash->{'address_start'} : 0;
		my $addressStep = $peeringHash->{'address_step'} ? $peeringHash->{'address_step'} : 0; #Todo oder lieber 1
		my $addressCount = $peeringHash->{'count'} ? $peeringHash->{'count'} : 1;
		my $dbg = sprintf("0x%X",$addressStart);
		print Dumper ("getPeeringFromDevice Addr start: $dbg; step: $addressStep count: $addressCount");
		
		for (my $i=0 ; $i < $addressCount; $i++) { 
			$hash->{'PEERNR'} = $i;
		#	print Dumper ("getPeeringFromDevice DeviceHash" ,$hash);
					
			foreach my $peerParam (keys $peeringHash->{'parameter'}) {
				if ($peerParam eq 'actuator' || $peerParam eq 'sensor') {
					my $peerSensor = $peeringHash->{'parameter'}{$peerParam}; #array
			
					if (ref($peerSensor->{'physical'}) eq 'ARRAY') {
						my $peerHash;
						foreach my $phyHash (@{$peerSensor->{'physical'}}) {
      	#					print Dumper ("Teste:",$phyHash);
      						$peerHash->{'physical'} = $phyHash;
      						$peerHash->{'logical'} = $peeringHash->{'parameter'}{$peerParam}{'logical'};
      			
      						if ($phyHash->{'size'} eq '4') {
      							$retVal->{$peerParam}{'address'} = HM485::PeeringManager::getValueFromEepromData (
									$hash, $peerHash, $addressStart, $addressStep
								);
								$retVal->{$peerParam}{'address'} = sprintf("%08X",$retVal->{$peerParam}{'address'});
      						}
      						if ($phyHash->{'size'} eq '1') {
      							$retVal->{$peerParam}{'channel'} = HM485::PeeringManager::getValueFromEepromData (
									$hash, $peerHash, $addressStart, $addressStep
								) +1;
      						}
      					}	
					}
				} elsif ($peerParam eq 'channel'){ #actuator und sensor
				  	$retVal->{'peerchannel'} = HM485::PeeringManager::getValueFromEepromData (
						$hash, $peeringHash->{'parameter'}{$peerParam}, $addressStart, $addressStep
					) +1 ;
				}
			} #foreach
		print Dumper("getPeeringFromDevice,$chNr",$retVal);
		last if ($retVal->{'peerchannel'} eq '256');
		} #for schleife
		
	} #if HASH
	
	return $retVal;
}

=head2 getPeeringSettings
	Get channel specific peering settings from device config file 
	
	@param	hash
	@param	int   the channel number
	
	@return	hash
=cut
sub getPeeringSettings($) {
	my ($hash) = @_;
	#print Dumper ("getPeeringSettings, $hash->{'DEF'}");
	#Todo Hier kommt auch noch ein leerer parameter hash, woher kommt der?
	my ($hmwId, $chNr) = HM485::Util::getHmwIdAndChNrFromHash($hash);
	my $devHash = $main::modules{'HM485'}{'defptr'}{substr($hmwId,0,8)};
	my $peerSettings = {};

	# Todo: Caching for Peering
#	my $peerSettings = $devHash->{cache}{peerSettings};
#	if (!$configSettings) {
		my $name   = $devHash->{'NAME'};
		my $deviceKey = HM485::Device::getDeviceKeyFromHash($devHash);
		
		if ($deviceKey && defined $chNr) {
			my $chType  = HM485::Device::getChannelType($deviceKey, $chNr);
			
			$peerSettings = HM485::Device::getValueFromDefinitions(
			 	$deviceKey . '/channels/' . $chType .'/paramset/link'
			);
		}

#		$devHash->{cache}{peerSettings} = $peerSettings;
#	}
	return $peerSettings;
}

sub getValueFromEepromData($$$$) {
	my ($hash, $configHash, $adressStart, $adressStep) = @_;
		
	my ($adrId, $size, $littleEndian) = getPhysicalAddress($hash, $configHash, $adressStart, $adressStep);
	
	my $retVal = '';
	if (defined($adrId)) {
		my $default;
		my $data = HM485::Device::getRawEEpromData(
			$hash, int($adrId), ceil($size), 0, $littleEndian 
		);
		#print Dumper ("getValueFromEepromData:getRawEEpromData",$data);
		my $eepromValue = 0;
		
		my $adrStart = (($adrId * 10) - (int($adrId) * 10)) / 10;
		
		$eepromValue = HM485::Device::getValueFromHexData($data, $adrStart, $size);
		#debug
		my $dbg = sprintf("0x%X",$adrId);
		my $eep = sprintf("0x%X",$eepromValue);
		#print Dumper ("getValueFromEepromDatahexdata:$adrStart, $dbg, $size, $littleEndian, $eep");
		
		$retVal = HM485::Device::dataConversion($eepromValue, $configHash->{'conversion'}, 'from_device');
		$default = $configHash->{'logical'}{'default'};
		
		if (defined($default)) {
			if ($size == 1) {
				$retVal = ($eepromValue != 0xFF) ? $retVal : $default;
			} elsif ($size == 2) {
				$retVal = ($eepromValue != 0xFFFF) ? $retVal : $default;
			} elsif ($size == 4) {
				$retVal = ($eepromValue != 0xFFFFFFFF) ? $retVal : $default; ##malsehen
			}
		}
	}
	return $retVal;
}

sub getPhysicalAddress($$$$) {
	my ($hash, $configHash, $adressStart, $adressStep) = @_;
		
	my $adrId = 0;
	my $size  = 0;
	my $littleEndian = 0;
	my $peerNr = $hash->{'PEERNR'};
	my ($hmwId, $chNr) = HM485::Util::getHmwIdAndChNrFromHash($hash);
	my $deviceKey = HM485::Device::getDeviceKeyFromHash($hash);
	my $chType         = HM485::Device::getChannelType($deviceKey, $chNr);
	my $chConfig  = HM485::Device::getValueFromDefinitions(
		$deviceKey . '/channels/' . $chType .'/'
	);
	my $chId = int($chNr) - $chConfig->{'index'}; ##OK
	my $peerId = int($peerNr); # - $chConfig->{'index'};
	#print Dumper ("getPhysicalAddress chId: $chId peerId: $peerId index: $chConfig->{'index'}");

	# we must check if special params exists.
	# Then address_id and step retreve from special params
	# There exists also Address Arrays
	
	if (exists $configHash->{'physical'}{'address'}{'index'}){
		my $valId        = $configHash->{'physical'}{'address'}{'index'};
		my $spConfig     = $chConfig->{'special_param'}{$valId};
		if ($spConfig) {
			$adressStep  = $spConfig->{'physical'}{'address_step'} ? $spConfig->{'physical'}{'address_step'}  : 0;
			$size        = $spConfig->{'physical'}{'size'}         ? $spConfig->{'physical'}{'size'} : 1;
			$adrId       = $spConfig->{'physical'}{'address'}{'index'}   ? $spConfig->{'physical'}{'address'}{'index'} : 0;
			$adrId       = $adrId + ($peerId * $adressStep * ceil($size));
		} else {
			$size       = $configHash->{'physical'}{'size'} ? $configHash->{'physical'}{'size'} : 1;
			$adrId      = $configHash->{'physical'}{'address'}{'index'} ? $configHash->{'physical'}{'address'}{'index'} : 0;
			$adrId      = $adrId + $adressStart + ($peerId * $adressStep);
		}
		$littleEndian = ($configHash->{'physical'}{'endian'} && $configHash->{'physical'}{'endian'} eq 'little') ? 1 : 0;
	}
	return ($adrId, $size, $littleEndian);
}


1;