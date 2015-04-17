package HM485::ConfigurationManager;

use strict;
use warnings;
use POSIX qw(ceil);

use Data::Dumper;

=head2 getConfigFromDevice
	Get config from Device
	
	@param	hash
	@param	int   the channel number
	

	@return	hash
=cut
sub getConfigFromDevice($$) {
	my ($hash, $chNr) = @_;
	#Todo wird 2 mal aufgerufen suchen von wo und warum
	
	my $retVal = {};
	my $configHash = getConfigSettings($hash);

	if (ref($configHash) eq 'HASH') {
		
		if (ref($configHash->{'parameter'}) eq 'HASH') {
			if ($configHash->{'parameter'}{'id'}) {
				#wenns eine id gibt sollte es keinen extra hash mit dem namen geben
				my $id = $configHash->{'parameter'}{'id'};
				$retVal->{$id} = writeConfigParameter($hash,$chNr,
					$configHash->{'parameter'},
					$configHash->{'address_start'},
					$configHash->{'address_step'}
				);
			# mehrere Config Parameter
			} else {
				foreach my $config (keys $configHash->{'parameter'}) {
					if (ref($configHash->{'parameter'}{$config}) eq 'HASH') {
						$retVal->{$config} = writeConfigParameter($hash,$chNr,
							$configHash->{'parameter'}{$config},
							$configHash->{'address_start'},
							$configHash->{'address_step'}
						);
					}
				}	
			}
		}
	}
	#print Dumper("getConfigFromDevice,$chNr");
	return $retVal;
}

sub writeConfigParameter($$$;$$) {
	my ($hash, $chNr, $parameterHash, $addressStart, $addressStep) = @_ ;
	
	my $retVal = {};
	my $type   = $parameterHash->{'logical'}{'type'} ? $parameterHash->{'logical'}{'type'} : undef;
	my $unit   = $parameterHash->{'logical'}{'unit'} ? $parameterHash->{'logical'}{'unit'} : '';
	my $min    = defined($parameterHash->{'logical'}{'min'})  ? $parameterHash->{'logical'}{'min'}  : undef;
	my $max    = defined($parameterHash->{'logical'}{'max'})  ? $parameterHash->{'logical'}{'max'}  : undef;

	$retVal->{'type'}  = $type;
	$retVal->{'unit'}  = $unit;
	
	if ($type && $type ne 'option') {
		#todo da gibts da noch mehr ?
		if ($type ne 'boolean') {
			$retVal->{'min'} = $min;
			$retVal->{'max'} = $max;
		}
	} else {
		#Todo gleich hier was anständiges reinschreiben
		#und einmal nachsehen, ob Default bits immer 1 sind
		#dann würde auch optionsToArray wieder einen Sinn machen
		#ist ja zur Zeit Options to String 
		#zb puschbutton => 1
		#   switch => 0
		$retVal->{'possibleValues'} = $parameterHash->{'logical'}{'option'};
	}
	
	my $addrStart = $addressStart ? $addressStart : 0;
	#address_steps gibts mehrere Varianten
	my $addrStep = $addressStep ? $addressStep : 0;
	if( $parameterHash->{'physical'}{'address'}{'step'}) {
		$addrStep = $parameterHash->{'physical'}{'address'}{'step'};
	}

	###debug Dadurch wird allerdings getPhysicalAddress 2 mal hintereinander aufgerufen !
	my ($addrId, $size, $endian) = HM485::Device::getPhysicalAddress(
				$hash, $parameterHash, $addrStart, $addrStep);
	
	$retVal->{'address_start'} = $addrStart;
	$retVal->{'address_step'} = $addrStep;
	$retVal->{'address_index'} = $addrId;
	$retVal->{'size'} = $size;
	$retVal->{'endian'} = $endian;
	####
	$retVal->{'value'} = HM485::Device::getValueFromEepromData (
		$hash, $parameterHash, $addrStart, $addrStep
	);

	return $retVal;
}

sub optionsToArray($) {
	my ($optionList) = @_;
	#Todo schöner programmieren ist a bissl umständlich geschrieben
	#der Name ist eigenlich auch falsch ist kein Array sondern 
	#ein string Komma separiert
	
	if (ref $optionList eq 'HASH') {
		my @map;
		my $default;
		my $nodefault;
		
		foreach my $oKey (keys %{$optionList}) {
			#das geht bestimmt schöner! zuerst default suchen und danach nochmal alles wieder durchsuchen?
			if (defined( $optionList->{$oKey}{default})) {
				$default = $optionList->{$oKey}{default};
				if ($default eq '1') {
					$nodefault = 0;
				} else {
					$nodefault = 1;
				}
			}
		}
		foreach my $oKey (keys %{$optionList}) {
			if (defined( $optionList->{$oKey}{default})) {
				push (@map, $oKey.':'.$default);
			} else {
				push (@map, $oKey.':'.$nodefault);
			}
		}
		return join(",",@map);
	} else {
		return map {s/ //g; $_; } split(',', $optionList);
	}
}

# Todo: Check if used anymore
sub convertOptionToValue($$) {
	my ($optionList, $option) = @_;

	my $retVal = 0;
	my @optionValues = optionsToArray($optionList);
	my $i = 0;

	foreach my $optionValue (@optionValues) {
		if ($optionValue eq $option) {
			$retVal = $i;
			last;
		}
		$i++;
	}
	#print Dumper ("convertOptionToValue:$option <> $retVal");
	return $retVal;
}

=head2 getConfigSettings
	Get channel specific config from device config file 
	
	@param	hash
	@param	int   the channel number
	
	@return	hash
=cut
sub getConfigSettings($) {
	my ($hash) = @_;
	#Todo Hier kommt auch noch ein leerer parameter hash, woher kommt der?
	my ($hmwId, $chNr) = HM485::Util::getHmwIdAndChNrFromHash($hash);
	my $devHash = $main::modules{'HM485'}{'defptr'}{substr($hmwId,0,8)};
	my $configSettings = {};

	# Todo: Caching for Config
#	my $configSettings = $devHash->{cache}{configSettings};
#	if (!$configSettings) {
		my $name   = $devHash->{'NAME'};
		my $deviceKey = HM485::Device::getDeviceKeyFromHash($devHash);
		
		if ($deviceKey && defined $chNr) {
			my $chType  = HM485::Device::getChannelType($deviceKey, $chNr);
			
			if ($chNr == 0 && $chType eq 'maintenance') {
				#channel 0 has a different path and has no address_start and address_step
				$configSettings = HM485::Device::getValueFromDefinitions(
				 	$deviceKey . '/paramset'
				);
			} else {
				$configSettings = HM485::Device::getValueFromDefinitions(
				 	$deviceKey . '/channels/' . $chType .'/paramset/master'
				);
			}
			if (ref($configSettings) eq 'HASH') {
				if (exists $configSettings->{'parameter'}{'id'}) {
					#print Dumper ("getConfigSettings vor convertIdToHash:");
					#rewrite Config ID
					#$configSettings->{'parameter'} = HM485::Util::convertIdToHash($configSettings->{'parameter'});
				#	print Dumper ("getConfigSettings:convertIdToHash",$configSettings);
				}
				
				# delete hidden configs
				foreach my $config (keys $configSettings->{'parameter'}) {
					if (ref($configSettings->{'parameter'}{$config}) eq 'HASH' && $configSettings->{'parameter'}{$config}{'hidden'}) {
						delete($configSettings->{'parameter'}{$config});
					}
				}	
			}
		}

#		$devHash->{cache}{configSettings} = $configSettings;
#	}
	return $configSettings;
}

sub convertSettingsToEepromData($$) {
	my ($hash, $configData) = @_;

	my $adressStart = 0;
	my $adressStep  = 0;
	my ($hmwId, $chNr) = HM485::Util::getHmwIdAndChNrFromHash($hash);
	
	my $adressOffset = 0;
	if ($chNr > 0) { #im channel 0 gibt es nur address index kein address_start oder address_step
		my $deviceKey    = HM485::Device::getDeviceKeyFromHash($hash);
		my $chType       = HM485::Device::getChannelType($deviceKey, $chNr);
		my $masterConfig = HM485::Device::getValueFromDefinitions(
			$deviceKey . '/channels/' . $chType . '/paramset/master'
		);
		$adressStart = $masterConfig->{'address_start'} ? $masterConfig->{'address_start'} : 0;
		$adressStep  = $masterConfig->{'address_step'}  ? $masterConfig->{'address_step'} : 1;
		
		$adressOffset = $adressStart + ($chNr - 1) * $adressStep;
	}
	
	my $addressData = {};
	foreach my $config (keys %{$configData}) {
		my $configHash     = $configData->{$config}{'config'};
		my ($adrId, $size, $littleEndian) = HM485::Device::getPhysicalAddress(
			$hash, $configHash, $adressStart, $adressStep
		);
		
		my $value = $configData->{$config}{'value'};
		
		if ($configData->{$config}{'config'}{'logical'}{'type'} eq 'option') {
			#$value = convertOptionToValue(
			#	$configData->{$config}{'config'}{'logical'}{'option'}, $value
			#);
		} else {
			$value = HM485::Device::dataConversion(
				$value, $configData->{$config}{'config'}{'conversion'}, 'to_device'
			);
		}

		my $adrKey = int($adrId);

		if (HM485::Device::isInt($size)) {
			$addressData->{$adrKey}{'value'} = $value;
			$addressData->{$adrKey}{'text'} = $config . '=' . $configData->{$config}{'value'};
			$addressData->{$adrKey}{'size'} = $size;
		} else {
			if (!defined($addressData->{$adrKey}{'value'})) {
				my $eepromValue = HM485::Device::getValueFromEepromData (
					$hash, $configData->{$config}{'config'}, $adressStart, $adressStep, 1
				);
				$addressData->{$adrKey}{'value'} = $eepromValue;
				$addressData->{$adrKey}{'text'} = '';
				$addressData->{$adrKey}{'size'} = ceil($size); ## ceil warum ?
			}

			my $bit = ($adrId * 10) - ($adrKey * 10);
			$addressData->{$adrKey}{'_adrId'} = $adrId;
			$addressData->{$adrKey}{'_value_old'} = $addressData->{$adrKey}{'value'};
			$addressData->{$adrKey}{'_value'} = $value;

			if ($value) { #value=1
				my $bitMask = 1 << $bit;
				$value = $addressData->{$adrKey}{'value'} | $bitMask;
			} else { #value=0
				my $bitMask = unpack ('C', pack 'c', ~(1 << $bit));
				$value = $addressData->{$adrKey}{'value'} & $bitMask;
			}
			$addressData->{$adrKey}{'text'} .= ' ' . $config . '=' . $configData->{$config}{'value'}
		}
		
		if ($littleEndian) {
			$value = sprintf ('%0' . ($size*2) . 'X' , $value);
			$value = reverse( pack('H*', $value) );
			$value = hex(unpack('H*', $value));
		}

		$addressData->{$adrKey}{'value'} = $value;
	}
	#print Dumper ("convertSettingsToEepromData,",$addressData);
	return $addressData;
}

1;