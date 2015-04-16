package HM485::Devicefile;
use constant false => 0;
use constant true => 1;

package HM485::Device;

use strict;
use warnings;
use Data::Dumper;
use Scalar::Util qw(looks_like_number);
use POSIX qw(ceil);

use Cwd qw(abs_path);
use FindBin;
use lib abs_path("$FindBin::Bin");
use lib::HM485::Constants;

#use vars qw {%attr %defs %modules}; #supress errors in Eclipse EPIC

# prototypes
sub parseForEepromData($;$$);

my %deviceDefinitions;
my %models = ();

=head2
	Initialize all devices
	Load available device files
=cut
sub init () {
	my $retVal      = '';
	my $devicesPath = $main::attr{global}{modpath} . HM485::DEVICE_PATH;

	if (opendir(DH, $devicesPath)) {
		HM485::Util::logger(HM485::LOGTAG_HM485, 3, 'HM485: Loading available device files');
		HM485::Util::logger(HM485::LOGTAG_HM485, 3, '=====================================');
		foreach my $m (sort readdir(DH)) {
			next if($m !~ m/(.*)\.pm$/);
			
			my $deviceFile = $devicesPath . $m;
			if(-r $deviceFile) {
				HM485::Util::logger(HM485::LOGTAG_HM485, 3, 'Loading device file: ' .  $deviceFile);
				my $includeResult = do $deviceFile;
	
				if($includeResult) {
					foreach my $dev (keys %HM485::Devicefile::definition) {
						$deviceDefinitions{$dev} = $HM485::Devicefile::definition{$dev};
					}
				} else {
					HM485::Util::logger(
						HM485::LOGTAG_HM485, 3,
						'HM485: Error in device file: ' . $deviceFile . ' deactivated:' . "\n $@"
					);
				}
				%HM485::Devicefile::definition = ();

			} else {
				HM485::Util::logger(
					HM485::LOGTAG_HM485, 1,
					'HM485: Error loading device file: ' .  $deviceFile
				);
			}
		}
		closedir(DH);
	
		if (scalar(keys %deviceDefinitions) < 1 ) {
			return 'HM485: Warning, no device definitions loaded!';
		}
	
		initModels();
	} else {
		$retVal = 'HM485: ERROR! Can\'t read devicePath: ' . $devicesPath . $!;
	}
		
	return $retVal;
}

=head2
	Initialize all loaded models
=cut
sub initModels () {

	foreach my $deviceKey (keys %deviceDefinitions) {
		if ($deviceDefinitions{$deviceKey}{'supported_types'}) {
			foreach my $modelKey (keys (%{$deviceDefinitions{$deviceKey}{'supported_types'}})) {
				if ($deviceDefinitions{$deviceKey}{'supported_types'}{$modelKey}{'parameter'}{'0'}{'const_value'}) {
					$models{$modelKey}{'model'} = $modelKey;
					$models{$modelKey}{'name'} = $deviceDefinitions{$deviceKey}{'supported_types'}{$modelKey}{'name'};
					$models{$modelKey}{'type'} = $deviceDefinitions{$deviceKey}{'supported_types'}{$modelKey}{'parameter'}{'0'}{'const_value'};
					
					my $minFW = $deviceDefinitions{$deviceKey}{'supported_types'}{$modelKey}{'parameter'}{'2'}{'const_value'};
					$minFW = $minFW ? $minFW : 0;
					$models{$modelKey}{'versionDeviceKey'}{$minFW} = $deviceKey; 
				}
			}
		}
	}
#	my $t = getModelName(getModelFromType(91));
}

=head2
	Get device key depends on firmware version
=cut
sub getDeviceKeyFromHash($) {
	my ($hash) = @_;

	my $retVal = '';
	if ($hash->{'MODEL'}) {
		my $model    = $hash->{'MODEL'};
		my $fw  = $hash->{'FW_VERSION'} ? $hash->{'FW_VERSION'} : 0;
		my $fw1 = $fw ? int($fw) : 0;
		my $fw2 = ($fw * 100) - int($fw) * 100;

		my $fwVersion = hex(
			sprintf ('%02X%02X', ($fw1 ? $fw1 : 0), ($fw2 ? $fw2 : 0))
		);

		foreach my $version (keys (%{$models{$model}{'versionDeviceKey'}})) {
			if ($version <= $fwVersion) {
				$retVal = $models{$model}{'versionDeviceKey'}{$version};
			} else {
				last;
			}
		}
	}
	
	return $retVal;
}


=head2
	Get the model from numeric hardware type
	
	@param	int      the numeric hardware type
	@return	string   the model
=cut
sub getModelFromType($) {
	my ($hwType) = @_;
	my $retVal = undef;

	foreach my $model (keys (%models)) {
		if (exists($models{$model}{'type'}) && $models{$model}{'type'} == $hwType) {
			$retVal = $model;
			last;
		}
	}

	return $retVal;
}

=head2 getModelName
	Get the model name from model type
	
	@param	string   the model type e.g. HMW_IO_12_Sw7_DR
	@return	string   the model name
=cut
sub getModelName($) {
	my ($hwType) = @_;
	my $retVal = 'unknown';

	if (defined($models{$hwType}{'name'})) {
		$retVal = $models{$hwType}{'name'};
	}
	
	return $retVal;
}

=head2 getModelList
	Get a list of models from $models hash

	@return	string   list of models
=cut
sub getModelList() {
	my @modelList;
	foreach my $type (keys %models) {
		if ($models{$type}{'model'}) {
			push (@modelList, $models{$type}{'model'});
		}
	}

	return join(',', @modelList);
}

=head2 getChannelBehaviour
	Get the behavior of a chanel from eeprom, if the channel support this

	@param	hash

	@return	array   array of behavior values
=cut
sub getChannelBehaviour($) {
	my ($hash) = @_;
	my $retVal = undef;
	
	my ($hmwId, $chNr) = HM485::Util::getHmwIdAndChNrFromHash($hash);

	if (defined($chNr)) {
		my $deviceKey = getDeviceKeyFromHash($hash);
		
		if ($deviceKey) {
			my $chType = HM485::Device::getChannelType($deviceKey, $chNr); #key
			
			my $channelConfig  = getValueFromDefinitions(
				$deviceKey . '/channels/' . $chType
			);
			
			if ($channelConfig->{'special_parameter'}{'id'} &&
			   ($channelConfig->{'special_parameter'}{'id'} eq 'behaviour') &&
			    $channelConfig->{'special_parameter'}{'physical'}{'address'}{'index'}) {
					my $chConfig = HM485::ConfigurationManager::getConfigFromDevice(
						$hash, $chNr
					);
					#print Dumper ("getChannelBehaviour:$chConfig->{'behaviour'}{'value'}");
				
				my $possibleValues = HM485::ConfigurationManager::optionsToArray($chConfig->{'behaviour'}{'possibleValues'});
				my @possibleValuesArray = split(',', $possibleValues); ###Todo kein arrray sondern string
				my $value = $chConfig->{'behaviour'}{'value'};	
				# Trim all items in the array
				foreach my $item (@possibleValuesArray) {
					my ($command, my $num) = split(':', $item);
					if ($value eq $num) {
						$retVal = $command;
						last;
					}
				}
			}
		}
	}
	print Dumper ("getChannelBehaviour:$retVal");
	return $retVal;
}

sub getBehaviourCommand($) {
	my ($hash) = @_;
	my $retVal = undef;
	
	my ($hmwId, $chNr) = HM485::Util::getHmwIdAndChNrFromHash($hash);

	if (defined($chNr)) {
		my $deviceKey = getDeviceKeyFromHash($hash);
		
		if ($deviceKey) {
			my $chType = HM485::Device::getChannelType($deviceKey, $chNr); #key
			my $channelConfig  = getValueFromDefinitions(
				$deviceKey . '/channels/' . $chType
			);
			
			if ($channelConfig->{'special_parameter'}{'id'} &&
			   ($channelConfig->{'special_parameter'}{'id'} eq 'behaviour') &&
			    $channelConfig->{'special_parameter'}{'physical'}{'address'}{'index'}) {
					my $chConfig = HM485::ConfigurationManager::getConfigFromDevice(
						$hash, $chNr
					);

				if ($chConfig->{'behaviour'}{'value'} eq '1') {
					my $search  = getValueFromDefinitions(
						$deviceKey . '/channels/' . $chType .'/subconfig/paramset/'
					);
					if (ref($search) eq 'HASH') {
						#leider kann getValueFromDefinitions nicht tiefer suchen
						foreach my $valueHash (keys %{$search}) {
							my $item = $search->{$valueHash};
							foreach my $found (keys %{$item}) {
								if ($found eq 'type' && $search->{$valueHash}{$found} eq 'values') {
									$retVal = $search->{$valueHash}{'parameter'};
								}
							}
						}
					}
				}				
			}
		}
	}
	#print Dumper ("getBehaviour",$retVal);
	return $retVal;
}




### we should rework below this ###


=head2 getHwTypeList
	Title		: getHwTypeList
	Usage		: my $modelHwList = getHwTypeList();
	Function	: Get a list of model harwaretypes from $models hash
	Returns 	: string
	Args 		: nothing
=cut
sub getHwTypeList() {
	print Dumper ("getHwTypeList");
	#Todo die; ich glaub das wird nicht mehr verwendet
	return join(',', sort keys %models);
}

=head2 getValueFromDefinitions
	Get values from definition hash by given path.
	The path is seperated by "/". E.g.: 'HMW_IO12_SW7_DR/channels/KEY'
	
	Special path segment can be "key:value". So we can select a hash contains a
	key and match the value. E.g. 'HMW_IO12_SW7_DR/channels/KEY/paramset/type:MASTER'
	
	@param	string	$path
	
	@return	mixed
=cut
sub getValueFromDefinitions ($) {
	my ($path) = @_;
	
	my $retVal = undef;
	my @pathParts = split('/', $path);
	my %definitionPart = %deviceDefinitions;

	my $found = 1;
	foreach my $part (@pathParts) {

		my ($subkey, $compare) = split(':', $part);
		if (defined($subkey) && defined($compare)) {
			$part = HM485::Util::getHashKeyBySubkey({%definitionPart}, $subkey, $compare);
		}

		if (defined($part)) {
			if (ref($definitionPart{$part}) eq 'HASH') {
				#we convert id=name to hash{name} ich weis noch nicht ob ich das wirklich will!!!
				#if (exists($definitionPart{$part}{'id'})) {
					#print Dumper ("getValueFromDefinitions ID Exists");
				#	$definitionPart{$part} = HM485::Util::convertIdToHash($definitionPart{$part});
					#print Dumper ("converted",$definitionPart{$part});
				#}
				%definitionPart = %{$definitionPart{$part}};
				
			} else {
				if ($definitionPart{$part}) {
					$retVal = $definitionPart{$part};
				} else {
					$retVal = undef;
					$found = 0;			
				}
				last;
			}
		} else {
			$found = 0;
			last;
		}
	}
	
	if (!defined($retVal) && $found) {
		$retVal = {%definitionPart};
	}
	return $retVal
}

=head2 getChannelType
	Get a type of a given channel number
	
	@param	string   the device key
	@param	int      the channel number
	
	@return	string   the channel type
=cut
sub getChannelType($$) {
	my ($deviceKey, $chNo) = @_;
	$chNo = int($chNo);
	
	my $retVal = undef;

	my $channels = getValueFromDefinitions($deviceKey . '/channels/');
	my @chArray  = getChannelsByModelgroup($deviceKey);

	foreach my $channel (@chArray) {
		my $chStart = int($channels->{$channel}{'index'});
		my $chCount = int($channels->{$channel}{'count'});
		if (($chNo == 0 && $chStart == 0) || ($chNo >= $chStart && $chNo < ($chStart + $chCount) && $chStart > 0)) {

			$retVal = $channel;
			last;
		}
	}
	return $retVal;
}

=head2
	Parse incomming frame data and split to several values
	
	@param	hash	the hash of the IO device
	@param	string	message to parse
=cut
sub parseFrameData($$$) {
	my ($hash, $data, $actionType) = @_;
	
	my $deviceKey        = HM485::Device::getDeviceKeyFromHash($hash);
	 #weil info_frequency und info_level gleiche id haben
	my $channel          = hex(substr($data, 2,2));
	my $hmwId            = $hash->{'DEF'}; 
	my $chHash           = $main::modules{'HM485'}{'defptr'}{$hmwId . '_' . $channel};
	my $channelBehaviour = HM485::Device::getChannelBehaviour($chHash);
	
	my $frameData        = getFrameInfos($deviceKey, $data, 1, $channelBehaviour, 'from_device');
	my $retVal           = convertFrameDataToValue($hash, $deviceKey, $frameData);
	return $retVal;
}

=head2
	Get all infos of current frame data
	
	@param	string	the deviceKey
	@param	string	the frame data to parse
	@param	boolean	optinal value identify the frame as event 
	@param	string	optional frame direction (from or to device)
=cut
sub getFrameInfos($$;$$$) {
	my ($deviceKey, $data, $event, $behaviour, $dir) = @_;
			
	my $frameType = hex(substr($data, 0,2));
	my %retVal;
	
	my $frames = getValueFromDefinitions($deviceKey . '/frames/');
	
	if ($frames) {
		foreach my $frame (keys %{$frames}) {
			if ($frames->{$frame}{'parameter'}{'index'}) {
				#we rewrite the new configuration to the old one
				my $replace = convertFrameIndexToHash ($frames->{$frame}{'parameter'});
				delete ($frames->{$frame}{'parameter'});
				$frames->{$frame}{'parameter'} = $replace;
			}
			#info_frequency auslassen wenn behaviour gesetzt ist da
			#'type' => 105 info_level , und 105 info_frequency gleich
			#und info_level eine size von 2 hat info_frequency jedoch 3
			#Todo evtl. gehts noch irgendwie anders wenn ein frame empfangen
			#wird, bis dahin halt so
			
			if (!$behaviour) {
				#print Dumper ("behaviour ist Nicht gesetzt");
				if ($frame eq 'info_frequency') {next;}
			}
						
			my $fType  = $frames->{$frame}{'type'};
			my $fEvent = $frames->{$frame}{'event'} ? $frames->{$frame}{'event'} : 0;
			my $fDir   = $frames->{$frame}{'direction'} ? $frames->{$frame}{'direction'} : 0;
			
			#print Dumper ("getFrameInfos ", $behaviour, $deviceKey,$event,$frame, $frames->{$frame});
			
			if ($frameType == $fType &&
			   (!defined($event) || $event == $fEvent) &&
			   (!defined($event) || $dir eq $fDir) ) {
				my $chField = ($frames->{$frame}{'channel_field'} - 9) * 2; #?für was ist das?
				my $parameter = translateFrameDataToValue($data, $frames->{$frame}{'parameter'});
				if (defined($parameter)) { #Daten umstrukturieren
					foreach my $pindex (keys %{$parameter}) {
						my $replace = $parameter->{$pindex}{'param'};
						$parameter->{$replace} = delete $parameter->{$pindex};
						delete $parameter->{$replace}{'param'};
					}
				}

				if (defined($parameter)) {
					%retVal = (
						ch     => sprintf ('%02d' , hex(substr($data, $chField, 2)) + 1),
						params => $parameter,
						type   => $fType,
						event  => $frames->{$frame}{event} ? $frames->{$frame}{event} : 0,
						id     => $frame
					);
					last;
				}
			}
		}
	}
	
	return \%retVal;
}

sub convertFrameIndexToHash($) {
	my ($configSettings) = @_;
	
	my $ConvertHash = {};
	my $index = sprintf("%.1f",$configSettings->{'index'});
	
	if ($index) {
		$ConvertHash->{$index} = $configSettings;
		delete $ConvertHash->{$index}{'index'};
	}
	
	return $ConvertHash;
}

sub getValueFromEepromData($$$$;$) {
	my ($hash, $configHash, $adressStart, $adressStep, $wholeByte) = @_;
	
	$wholeByte = $wholeByte ? 1 : 0;
	my $retVal = '';

	my ($adrId, $size, $littleEndian) = getPhysicalAddress($hash, $configHash, $adressStart, $adressStep);
	
	if (defined($adrId)) {
		my $default;
		my $data = HM485::Device::getRawEEpromData(
			$hash, int($adrId), ceil($size), 0, $littleEndian 
		);
		my $eepromValue = 0;
		
		my $adrStart = (($adrId * 10) - (int($adrId) * 10)) / 10;
		$adrStart    = ($adrStart < 1 && !$wholeByte) ? $adrStart: 0;
		$size        = ($size < 1 && $wholeByte) ? 1 : $size;
		
		$eepromValue = getValueFromHexData($data, $adrStart, $size);
		#debug
		my $dbg = sprintf("0x%X",$adrId);
		my $eep = sprintf("0x%X",$eepromValue);
		#print Dumper ("getValueFromEepromDatahexdata:$adrStart, $dbg, $size, $littleEndian, $eep");
		
		if ($wholeByte == 0) {
			$retVal = dataConversion($eepromValue, $configHash->{'conversion'}, 'from_device');
			$default = $configHash->{'logical'}{'default'};
		} else { #dataConversion bei mehreren gesetzten bits ist wohl sinnlos kommt null raus
				 #auch ein default Value bringt teilweise nur Unsinn in solchen Fällen Richtig ???
			$retVal = $eepromValue;
		}
		
		if (defined($default)) {
			if ($size == 1) {
				$retVal = ($eepromValue != 0xFF) ? $retVal : $default;
			} elsif ($size == 2) {
				$retVal = ($eepromValue != 0xFFFF) ? $retVal : $default;
			} elsif ($size == 4) {
				$retVal = ($eepromValue != 0x00FFFFFF) ? $retVal : $default; ##malsehen
			}
		}
	}
	return $retVal;
}

sub getPhysicalAddress($$$$) {
	my ($hash, $configHash, $adressStart, $adressStep) = @_;
	#print Dumper ("getPhysicalAddress: $adressStart : $adressStep");
		
	my $adrId = 0;
	my $size  = 0;
	my $littleEndian = 0;
	my $chConfig = {};
	my ($hmwId, $chNr) = HM485::Util::getHmwIdAndChNrFromHash($hash);
	my $deviceKey = HM485::Device::getDeviceKeyFromHash($hash);
	my $chType         = HM485::Device::getChannelType($deviceKey, $chNr);
	$chConfig  = getValueFromDefinitions(
		$deviceKey . '/channels/' . $chType .'/'
	);
	my $chId = int($chNr) - $chConfig->{'index'}; ##OK

	# we must check if special params exists.
	# Then address_id and step retreve from special params
	if (exists $configHash->{'physical'}{'interface'}) {
		if ($configHash->{'physical'}{'interface'} eq 'internal') {
			my $spConfig  = HM485::Device::getValueFromDefinitions(
				$deviceKey . '/channels/' . $chType .'/special_parameter/'
			);
			if ($spConfig->{'id'} eq $configHash->{'physical'}{'value_id'}) {
				$adressStep  = $spConfig->{'physical'}{'address'}{'step'} ? $spConfig->{'physical'}{'address'}{'step'}  : 0;
				$size        = $spConfig->{'physical'}{'size'}         ? $spConfig->{'physical'}{'size'} : 1;
				$adrId       = $spConfig->{'physical'}{'address'}{'index'}   ? $spConfig->{'physical'}{'address'}{'index'} : 0;
				$adrId       = $adrId + ($chId * $adressStep * ceil($size));
			}			
		} else { ##eeprom
			if (exists $configHash->{'physical'}{'address'}{'index'}){
				my $valId   = $configHash->{'physical'}{'address'}{'index'};
				$size       = $configHash->{'physical'}{'size'} ? $configHash->{'physical'}{'size'} : 1;
				$adrId      = $configHash->{'physical'}{'address'}{'index'} ? $configHash->{'physical'}{'address'}{'index'} : 0;
				$adrId      = $adrId + $adressStart + ($chId * $adressStep);
				$littleEndian = ($configHash->{'physical'}{'endian'} && $configHash->{'physical'}{'endian'} eq 'little') ? 1 : 0;
			}
		}
	}
	
	return ($adrId, $size, $littleEndian);
}


#hier gibt es 2 versionen
sub translateFrameDataToValue($$) {
	my ($data, $params) = @_;
	$data = pack('H*', $data);
	my $dataValid = 1;
	my %retVal;
	
	if ($params) {
		foreach my $param (keys %{$params}) {
			my $id    = ($param -9);
			my $size  = ($params->{$param}{'size'});
			my $value = getValueFromHexData($data, $id, $size);
			my $constValue = $params->{$param}{'const_value'};

			if (!$constValue || $constValue eq $value) {
				$retVal{$param}{val} = $value;
				if ($constValue) {
					$retVal{$param}{'param'} = 'const_value';
				} else {
					$retVal{$param}{'param'} = $params->{$param}{param};
				}
			} else {
				$dataValid = 0;
				last
			}
		}
	}
	
	return $dataValid ? \%retVal : undef;
}

sub getValueFromHexData($;$$) {
	my ($data, $start, $size) = @_;
	my $dbg = unpack ('H*',$data);
	#print Dumper ("getValueFromHexData",$data,$start,$size,$dbg);

	$start = $start ? $start : 0;
	$size  = $size ? $size : 1;

	my $retVal;

	if (isInt($start) && $size >=1) {
		#my $test = substr($data, $start, $size);
		#print Dumper ("getValueFromHexDatau:npack",$test);
		$retVal = hex(unpack ('H*', substr($data, $start, $size))); ##das funktioniert nicht richtig ?? bei size 4
	} else {
		my $bitsId = ($start - int($start)) * 10;
		my $bitsSize  = ($size - int($size)) * 10;
		$retVal = ord(substr($data, int($start), 1));
		$retVal = subBit($retVal, $bitsId, $bitsSize);
	}
	#print Dumper ("getValueFromHexData",$retVal);

	return $retVal;
}

sub convertFrameDataToValue($$$) {
	my ($hash, $deviceKey, $frameData) = @_;
	
	print Dumper ("convertFrameDataToValue $frameData->{'id'}");

	if ($frameData->{'ch'}) {
		foreach my $valId (keys %{$frameData->{'params'}}) {
			my $valueMap = getChannelValueMap($hash, $deviceKey, $frameData, $valId);
			if ($valueMap) {
				$frameData->{params}{$valId}{val} = dataConversion(
					$frameData->{params}{$valId}{val},
					$valueMap->{conversion},
					'from_device'
				);

				$frameData->{value}{$valueMap->{name}} = valueToControl(
					$valueMap,
					$frameData->{params}{$valId}{val},
					
				);
			}
		}
	}

	return $frameData;
}

=head2
	Map values to control specific values

	@param	hash    hash of parameter config
	@param	number    the data value
	
	@return string    converted value
=cut
sub valueToControl($$) {
	my ($paramHash, $value) = @_;
	
	my $retVal = $value;
	my $control = $paramHash->{'control'};
	my $valName = $paramHash->{'name'};

	if ($control) {
		if ($control eq 'switch.state') {
			my $threshold = $paramHash->{conversion}{threshold};
			$threshold = $threshold ? int($threshold) : 1;
			$retVal = ($value > $threshold) ? 'on' : 'off';

		} elsif ($control eq 'dimmer.level' || $control eq 'blind.level') {
			##Ich hoffe der multiplicator gehört hierher
			$retVal = $value * 100;

		} elsif (index($control, 'button.') > -1) {
			$retVal = $valName . ' ' . $value;

		} else {
			$retVal = $value;
		}

	} else {
		$retVal = $value;
	}
	
	return $retVal;
}

sub onOffToState($$) {
	my ($stateHash, $cmd) = @_;

	my $state = 0;
	my $conversionHash = $stateHash->{'conversion'};
	my $logicalHash = $stateHash->{'logical'};
	#Todo es gäbe auch: long_[on,off]_level short_[on,off]_level, wäre dann aus dem eeprom zu holen


	if ($cmd eq 'on') {
		if ($logicalHash->{'type'} eq 'boolean') {
			$state = $conversionHash->{true};
		} elsif ($logicalHash->{'type'} eq 'float') {
			$state = $conversionHash->{'factor'} * $logicalHash->{'max'};
		}
		
		
	} elsif ($cmd eq 'off') {
		if ($logicalHash->{'type'} eq 'boolean') {
			$state = $conversionHash->{false};
		} elsif ($logicalHash->{'type'} eq 'float') {
			$state = $conversionHash->{'factor'} * $logicalHash->{'min'};
		}
	}
	return $state;
}

sub valueToState($$$$) {
	my ($chType, $valueHash, $valueKey, $value) = @_;
	#da FHEM von 0 - 100 schickt und HMW 0-1
	$value = $value / 100;
	
	my $factor = $valueHash->{'conversion'}{'factor'} ? int($valueHash->{'conversion'}{'factor'}) : 1;
	my $state = int($value * $factor);
	return $state;
}

sub buildFrame($$$) {
	my ($hash, $frameType, $frameData) = @_;
	my $retVal;

	if (ref($frameData) eq 'HASH') {
		my ($hmwId, $chNr) = HM485::Util::getHmwIdAndChNrFromHash($hash);
		my $devHash        = $main::modules{HM485}{defptr}{substr($hmwId,0,8)};
		my $deviceKey      = HM485::Device::getDeviceKeyFromHash($devHash);

		my $frameHash = HM485::Device::getValueFromDefinitions(
			$deviceKey . '/frames/' . $frameType .'/'
		);

		if (ref($frameHash->{'parameter'}) eq 'HASH') {
			#we rewrite the new configuration to the old one
			foreach my $idx (keys $frameHash->{'parameter'}){
				if (ref($frameHash->{'parameter'}{$idx}) eq 'HASH' && $frameHash->{'parameter'}{$idx}{'size'}) {
					$frameHash->{'parameter'}{'size'} = $frameHash->{'parameter'}{$idx}{'size'};
					last;
				}
			}
		}
		

		$retVal = sprintf('%02X%02X', $frameHash->{'type'}, $chNr-1); ##OK
		

		foreach my $key (keys %{$frameData}) {
			my $valueId = $frameData->{$key}{'physical'}{'value_id'}; ##state

			if ($valueId && ref($frameHash->{'parameter'}) eq 'HASH') {
				my $paramLen = $frameHash->{'parameter'}{'size'} ? int($frameHash->{'parameter'}{'size'}) : 1;
				$retVal.= sprintf('%0' . $paramLen * 2 . 'X', $frameData->{$key}{'value'});
			}
		}
	}

	return $retVal;
}

=head2
	Convert values specifyed in config files

	@param	number    the value to convert
	@param	hast      convertConfig hash
	@param	string    the converting direction
	
	@return string    converted value
=cut
sub dataConversion($$;$) {
	my ($value, $convertConfig, $dir) = @_;
	
	my $retVal = $value;
	my $tmpConvertConfig = $convertConfig;
	if (ref($tmpConvertConfig) eq 'HASH') {
		$dir = ($dir && $dir eq 'to_device') ? 'to_device' : 'from_device';
		#Todo es gibt auch noch type in {'1' => {'type' => 'boolean_integer'}
		#ist hier das device.pm file noch zu machen ? oder stimmt das wirklich
		my $type = $tmpConvertConfig->{'type'};
		if (!$type) {
			#todo da geht noch mehr ich verstehs noch nicht ganz if type or value_map
			#es gibt nich nur {'1'}{'type'} auch 2 und 3 hab ich schon gesehen
			#ich glaube das muss nacheinander duchgeackert werden
			$type = $tmpConvertConfig->{'1'}{'type'};
			$tmpConvertConfig = $tmpConvertConfig->{'1'};
			if (!$type) {
				return $retVal;
			}
		}

		if (ref($tmpConvertConfig->{'value_map'}) eq 'HASH' && $tmpConvertConfig->{'value_map'}{'type'}) {
			foreach my $key (keys %{$tmpConvertConfig->{value_map}}) {
				my $valueMap = $tmpConvertConfig->{'value_map'}{$key};
				if (ref($valueMap) eq 'HASH') {

					if ($tmpConvertConfig->{'value_map'}{'type'} eq 'integer_integer_map') {
						my $valParam  = $valueMap->{'parameter_value'} ? $valueMap->{'parameter_value'} : 0;
						my $valDevice = $valueMap->{'device_value'} ? $valueMap->{'device_value'} : 0;
	
						if ($dir eq 'to_device' && $valueMap->{'to_device'}) {
							$retVal = ($value == $valParam) ? $valDevice : $retVal;
						} elsif ($dir eq 'from_device' && $valueMap->{'from_device'}) {
							$retVal = ($value == $valDevice) ? $valParam : $retVal;
						}
					}
				}
			}
		}

		if ($type eq 'float_integer_scale' || $type eq 'integer_integer_scale') {
			my $factor = $tmpConvertConfig->{'factor'} ? $tmpConvertConfig->{'factor'} : 1;
			my $offset = $tmpConvertConfig->{'offset'} ? $tmpConvertConfig->{'offset'} : 0;
			$factor = ($type eq 'float_integer_scale') ? $factor : 1;
#my $t = $retVal;
			if ($dir eq 'to_device') {
				$retVal = $retVal + $offset;
				$retVal = int($retVal * $factor); 
			} else {
#				$retVal = $retVal / $factor;
				if ($retVal ne "off" || $retVal ne "on") {
					$retVal = sprintf("%.2f", $retVal / $factor);
					$retVal = $retVal - $offset;
				}
			}
			
		} elsif ($type eq 'boolean_integer') {
			my $threshold = $tmpConvertConfig->{threshold} ? $tmpConvertConfig->{threshold} : 1;
			my $invert    = $tmpConvertConfig->{'invert'} ? 1 : 0;			
			my $false     = $tmpConvertConfig->{false} ? $tmpConvertConfig->{false} : 0;
			my $true      = $tmpConvertConfig->{true} ? $tmpConvertConfig->{true} : 1;

			if ($dir eq 'to_device') {
				$retVal = ($retVal >= $threshold) ? 1 : 0;
				$retVal = (($invert && $retVal) || (!$invert && !$retVal)) ? 0 : 1; 
			} else {
				$retVal = (($invert && $retVal) || (!$invert && !$retVal)) ? 0 : 1; 
				$retVal = ($retVal >= $threshold) ? $true : $false;
			}

		# Todo float_configtime from 
		#} elsif ($config eq 'float_configtime') {
		#	$valueMap = 'IntInt';

		#} elsif ($config eq 'option_integer') {
		#	$valueMap = 'value';

		}
	}
	
	return $retVal;
}

sub getChannelValueMap($$$$) {
	my ($hash, $deviceKey, $frameData, $valId) = @_;
	
	my $channel = $frameData->{'ch'};
	my $chType = getChannelType($deviceKey, $channel);

	my $hmwId = $hash->{'DEF'}; 
	my $chHash = $main::modules{'HM485'}{'defptr'}{$hmwId . '_' . $channel};

	my $values;
	my $channelBehaviour = HM485::Device::getChannelBehaviour($chHash);

# Todo: Check $channelBehaviour and $valuePrafix
	if ($channelBehaviour) {
		print Dumper ("getChannelValueMap channelbehaviour:$channelBehaviour");
	}
#	my $valuePrafix = $channelBehaviour ? '.' . $channelBehaviour : ''; ###digital_analog_output
	my $valuePrafix = '';    #hmw_analog_output_values wie krieg ich das ? bräuchte ich auch im behaviourcommand
	#$values  = getValueFromDefinitions( $deviceKey . '/channels/' . $chType . '/subconfig/paramset/');
	$values  = getValueFromDefinitions(
		$deviceKey . '/channels/' . $chType .'/paramset/values/parameter' . $valuePrafix . '/'
	);
	my $retVal;
	if (defined($values)) {
		print Dumper ("getChannelValueMap $valId");
		if (exists ($values->{'id'})) {
			#oh wie ich diese id's hasse :-(
			#print Dumper ("OJE eine ID getChannelValueMap",$values);
			$values = HM485::Util::convertIdToHash($values);
		}
		foreach my $value (keys %{$values}) {
			if ($values->{$value}{'physical'}{'value_id'} eq $valId) {
				if (!defined($values->{$value}{'physical'}{'event'}{'frame'}) ||
					$values->{$value}{'physical'}{'event'}{'frame'} eq $frameData->{'id'}
				) {
					$retVal = $values->{$value};
					$retVal->{'name'} = $value;
					last;
				}
			}
		}
	}
	return $retVal;
}

sub getEmptyEEpromMap ($) {
	my ($hash) = @_;

	my $deviceKey = HM485::Device::getDeviceKeyFromHash($hash);
	my $eepromAddrs = parseForEepromData(getValueFromDefinitions($deviceKey));
	
	#my $dbg = getValueFromDefinitions($deviceKey);
	print Dumper ("getEmptyEEpromMap",$deviceKey,$eepromAddrs);

	my $eepromMap = {};
	my $blockLen = 16;
	my $blockCount = 0;
	my $addrMax = 1024;
	my $adrCount = 0;
	my $hexBlock;

	for ($blockCount = 0; $blockCount < ($addrMax / $blockLen); $blockCount++) {
		my $blockStart = $blockCount * $blockLen;
		foreach my $adrStart (sort keys %{$eepromAddrs}) {
			my $len = $adrStart + $eepromAddrs->{$adrStart};
			if (($adrStart >= $blockStart && $adrStart < ($blockStart + $blockLen)) ||
			    ($len >= $blockStart)
			   ) {

				my $blockId = sprintf ('%04X' , $blockStart);
				if (!$eepromMap->{$blockId}) {
					$eepromMap->{$blockId} = '##' x $blockLen;
				}
				if ($len <= ($blockStart + $blockLen)) {
					delete ($eepromAddrs->{$adrStart});				
				}
			} else {
				last;
			}
		}
	}

	return $eepromMap;
}

=head2
	Get EEprom data from hash->READINGS with specific start address and lenth

	@param	hash       hash	hash of device addressed
	@param	int        start address
	@param	int        count bytes to retreve
	@param	boolean    if 1 return as hext string
	
	@return string     value string
=cut
sub getRawEEpromData($;$$$$) {
	my ($hash, $start, $len, $hex, $littleEndian) = @_;
	
	my $hmwId   = $hash->{'DEF'};
	my $devHash = $main::modules{'HM485'}{'defptr'}{substr($hmwId,0,8)};

	my $blockLen = 16;
	my $addrMax = 1024;
	my $blockStart = 0;
	my $blockCount = 0;
	
	$start        = defined($start) ? $start : 0;        #45
	$len          = defined($len) ? $len : $addrMax;	 #4     end = 45 + 4 = 49 
	$hex          = defined($hex) ? $hex : 0;
	$littleEndian = defined($littleEndian) ? $littleEndian : 0;

	if ($start > 0) {					     #ende  = 49 / 16 = 3,06 = int 3
		$blockStart = int($start/$blockLen); #start = 45 / 16 = 2,81 = int 2
	}

	my $retVal = ''; #      2                           =1024 / 16 ist immer 64 warum also ceil
	#for ($blockCount = $blockStart; $blockCount < (ceil($addrMax / $blockLen)); $blockCount++) {
	for ($blockCount = $blockStart; $blockCount < ($addrMax / $blockLen); $blockCount++) {
		my $blockId = sprintf ('.eeprom_%04X' , ($blockCount * $blockLen));
		if ($devHash->{'READINGS'}{$blockId}{'VAL'}) {
			$retVal.= $devHash->{'READINGS'}{$blockId}{'VAL'};
		} else {
			$retVal = 'FF' x $blockLen;
		}
		if (length($retVal) / 2 >= $start - $blockStart * $blockLen + $len) {
			last;
		}
	}
	
	my $start2 = ( ( ($start/$blockLen) - $blockStart ) * $blockLen );
	$retVal = pack('H*', substr($retVal, ($start2 * 2), ($len * 2) ) );
	
	$retVal = $littleEndian ? reverse($retVal) : $retVal;
	$retVal = $hex ? unpack('H*', $retVal) : $retVal;

	#my $dbg = unpack ('H*',$retVal);
	#print Dumper ("getRawEEpromData $start, $len $dbg");
	return $retVal;
}

sub setRawEEpromData($$$$) {
	my ($hash, $start, $len, $data) = @_;

	$data = substr($data, 0, ($len*2));
	$len = length($data);
	my $blockLen = 16;
	my $addrMax = 1024;
	my $blockStart = 0;
	my $blockCount = 0;
	
	if (hex($start) > 0) {
		$blockStart = int((hex($start) * 2) / ($blockLen*2));
	}

	for ($blockCount = $blockStart; $blockCount < (ceil($addrMax / $blockLen)); $blockCount++) {

		my $blockId = sprintf ('.eeprom_%04X' , ($blockCount * $blockLen));
		my $blockData = $hash->{'READINGS'}{$blockId}{'VAL'};
		if (!$blockData) {
			# no blockdata defined yet
			$blockData = 'FF' x $blockLen;
		}

		my $dataStart = (hex($start) * 2) - ($blockCount * ($blockLen * 2));
		my $dataLen = $len;

		if ($dataLen > (($blockLen * 2) - $dataStart)) {
			$dataLen = ($blockLen * 2) - $dataStart;
		}

		my $newBlockData = $blockData;

		if ($dataStart > 0) {
			$newBlockData = substr($newBlockData, 0, $dataStart);
		} else {
			$newBlockData = '';
		}

		$dataLen = ($len <= $dataLen) ? $len : $dataLen;
		$newBlockData.= substr($data, 0, $dataLen);

		if ($dataStart + $dataLen < ($blockLen * 2)) {
			$newBlockData.= substr(
				$blockData, ($dataStart + $dataLen), ($blockLen * 2) - $dataStart + $dataLen
			);
			$data = '';
		} else {
			$data = substr($data, $dataLen);
			$start = ($blockCount * $blockLen) + $blockLen;
		}
		
		$hash->{'READINGS'}{$blockId}{'VAL'} = $newBlockData;

		$len = length($data);
		if ($len == 0) {
			last;
		}
	}
}

=head2
	Walk thru device definition and found all eeprom related values
	
	Todo: Maybe we don't need the function. We should ask the device for used eeprom space
	
	@param	hash    the whole config for thie device
	@param	hash    holds the the eeprom adresses with length
	@param	hash    spechial params passed while recursion for getEEpromData
	
	@return hash    $adrHash
=cut
sub parseForEepromData($;$$) {
	my ($configHash, $adrHash, $params) = @_;

	$adrHash = $adrHash ? $adrHash : {};
	$params  = $params ? $params : {};
	
	# first we must collect all values only, hashes was pushed to hash array
	my @hashArray = ();
	
	foreach my $param (keys %{$configHash}) {
		if (ref($configHash->{$param}) ne 'HASH') {
			if ($param eq 'count' || $param eq 'address_start' || $param eq 'address_step') {
				$params->{$param} = $configHash->{$param};
				#bei io12sw14 gibts nur counts
			}
		} else {
			push (@hashArray, $param);
		}
	}
	# now we parse the hashes
	foreach my $param (@hashArray) {
		my $p = $configHash->{$param};
		# Todo: Processing Array of hashes (type array) 

		if ((ref ($p->{physical}) eq 'HASH') && $p->{physical} && $p->{physical}{interface} && ($p->{physical}{interface} eq 'eeprom') ) {
			my $result = getEEpromData($p, $params);
			@{$adrHash}{keys %$result} = values %$result;
		} else {
			$adrHash = parseForEepromData($p, $adrHash, {%$params});
		}
	}

	return $adrHash;
}

=head2
	calculate the eeprom adress with length for a specific param hash
	
	@param	hash    the param hash
	@param	hash    spechial params passed while recursion for getEEpromData

	@return hash    eeprom addr -> length
=cut
sub getEEpromData($$) {
	my ($paramHash, $params) = @_;
	print Dumper ("getEEpromData",$paramHash,$params);
#"physical" => {
#                                    "address" => {
#                                        "index" => 10,
#                                        "step" => 1
#                                    },
#                                    "interface" => "eeprom",
#                                    "size" => 1,
#                                    "type" => "integer"
#                                }

	my $count = ($params->{'count'} && $params->{'count'} > 0) ? $params->{'count'} : 1; 
	my $retVal;
	
	if ($params->{'address_start'} && $params->{'address_step'}) {
		my $adrStart  = $params->{'address_start'} ? $params->{'address_start'} : 0; 
		my $adrStep   = $params->{'address_step'} ? $params->{'address_step'} : 1;
		
		$adrStart = sprintf ('%04d' , $adrStart);
		$retVal->{$adrStart} = $adrStep * $count;
	#alternate Configuration
	} elsif ($params->{'address'}{'step'}) {
		my $adrStart  = 0;
		my $adrStep   = $paramHash->{'address'}{'step'} ? $paramHash->{'address'}{'step'} : 1;
		$adrStart = sprintf ('%04d' , $adrStart);
		$retVal->{$adrStart} = $adrStep * $count;

	} else {
		if ($paramHash->{'physical'}{'address_id'}) {
			my $adrStart =  $paramHash->{'physical'}{'address_id'};
			$adrStart = sprintf ('%04d' , $adrStart);

			my $size = $paramHash->{'physical'}{'size'};
			$size = $size * $count;
			$size = isInt($paramHash->{'physical'}{'size'}) ? $size : ceil(($size / 0.8));
			
			$retVal->{$adrStart} = $size;
		}
		#alternate Configuration
		if ($paramHash->{'physical'}{'address'}{'index'}) {
			my $adrStart =  $paramHash->{'physical'}{'address'}{'index'};
			$adrStart = sprintf ('%04d' , $adrStart);

			my $size = $paramHash->{'physical'}{'size'};
			$size = $size * $count;
			$size = isInt($paramHash->{'physical'}{'size'}) ? $size : ceil(($size / 0.8));
			
			$retVal->{$adrStart} = $size;
		}
	}

	return $retVal;
}

sub getChannelsByModelgroup ($) {
	my ($deviceKey) = @_;
	my $channels = getValueFromDefinitions($deviceKey . '/channels/');
	my @retVal = ();
	foreach my $channel (keys %{$channels}) {
		push (@retVal, $channel);
	}
	
	return @retVal;
}

sub isNumber($) {
	my ($value) = @_;
	
	my $retVal = (looks_like_number($value)) ? 1 : 0;
	
	return $retVal;
}

sub isInt($) {
	my ($value) = @_;
	
	$value = (looks_like_number($value)) ? $value : 0;
	my $retVal = ($value == int($value)) ? 1 : 0;
	
	return $retVal;
}

sub subBit ($$$) {
	my ($byte, $start, $len) = @_;
	
	return (($byte << (8 - $start - $len)) & 0xFF) >> (8 - $len);
}

sub internalUpdateEEpromData($$) {
	my ($devHash, $requestData) = @_;

	my $start = substr($requestData, 0,4);
	my $len   = substr($requestData, 4,2);
	my $data  = substr($requestData, 6);

	setRawEEpromData($devHash, $start, $len, $data);
}

sub parseModuleType($) {
	my ($data) = @_;
	
	my $modelNr = hex(substr($data,0,2));
	my $retVal   = getModelFromType($modelNr);
	$retVal =~ s/-/_/g;
	
	return $retVal;
}

sub parseSerialNumber($) {
	my ($data) = @_;
	
	my $retVal = substr(pack('H*',$data), 0, 10);
	
	return $retVal;
}

sub parseFirmwareVersion($) {
	my ($data) = @_;
	my $retVal = undef;
	
	if (length($data) == 4) {
		$retVal = hex(substr($data,0,2));
		$retVal = $retVal + (hex(substr($data,2,2))/100);
	}

	return $retVal;
}

sub getAllowedSets($) {
	my ($hash) = @_;
	
	my $name   = $hash->{'NAME'};
	my $model  = $hash->{'MODEL'};
	my $onOff  = 'on:noArg off:noArg ';
	my $keys   = 'press_short:noArg press_long:noArg';
	
	my %cmdOverwrite = (
		'switch.state'	=> "on:noArg off:noArg"
	);
		
	my %cmdArgs = (
		'none'			=> "noArg",
   		'blind.level'	=> "slider,0,1,100 on:noArg off:noArg",
   		'blind.stop'	=> "noArg",
   		'dimmer.level' 	=> "slider,0,1,100 on:noArg off:noArg",
   		'button.long'	=> "noArg",
   		'button.short'	=> "noArg",
   		'digital_analog_output.frequency' => "slider,0,1,100 frequency2:textField",
   		'door_sensor.state' => "feedbackerwünscht"
	);
	
	my @cmdlist;
	my $retVal = undef;

	if (defined($model) && $model) {
		
		my ($hmwId, $chNr) = HM485::Util::getHmwIdAndChNrFromHash($hash);

		if (defined($chNr)) {
			
			my $deviceKey = HM485::Device::getDeviceKeyFromHash($hash);
			my $chType    = getChannelType($deviceKey, $chNr);
			my $commands  = getValueFromDefinitions(
				$deviceKey . '/channels/' . $chType .'/paramset/values/parameter'
			);
				
			my $bahaviour = getBehaviourCommand($hash);
			if ($bahaviour) {
				$commands = $bahaviour;
			}
				
			if (exists ($commands->{'id'})) {
				#print Dumper ("OJE eine ID getAllowedSets"); 
				$commands = HM485::Util::convertIdToHash($commands);
			}
			foreach my $command (sort (keys %{$commands})) {
				if ($commands->{$command}{'operations'}) {
					my @values = split(',', $commands->{$command}{'operations'});
  					foreach my $val (@values) {
    					if ($val eq 'write' && $commands->{$command}{'physical'}{'interface'} eq 'command') {
							if ($commands->{$command}{'control'}) {
								my $ctrl = $commands->{$command}{'control'};
								if ($cmdOverwrite{$ctrl}) {
									push @cmdlist, $cmdOverwrite{$ctrl};
								}
								if($cmdArgs{$ctrl}) {
									push @cmdlist, "$command:$cmdArgs{$ctrl}";	
								}
							} else {
								push @cmdlist, "$command";
							}
						}
    				}
				}
			}
		}
	}
	$retVal = join(" ",@cmdlist);
	return $retVal;
}

1;