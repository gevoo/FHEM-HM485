package HM485::Devicefile;
our %definition = (
	'HBW_CC_VD2_T' => {
		'version' => 	14,
		'eep_size' => 	1024,
		'supported_types' => 	{
			"HMW_CC_Vd2_T" => {
				"name" => "RS485 Valve Actuator 2Channels",
				"parameter" => {
					0 => {
						"const_value" => 145,
						"size" => 1
					},
					1 => {
						"const_value" => 0,
						"size" => 1
					},
					2 => {
						"cond_op" => "GE",
						"const_value" => 0x0303,
						"size" => 2
					}
				},
				"priority" => 2
			}
		},
		'paramset' => 	{
			"enforce" => {
				"central_address" => {
					"value" => 1
				},
				"direct_link_deactivate" => {
					"value" => true
				}
			},
			"id" => "hmw-cc-vd2-t_dev_master",
			"parameter" => {
				"central_address" => {
					"hidden" => true,
					"logical" => {
						"type" => "integer"
					},
					"physical" => {
						"address" => {
							"index" => 0x0002
						},
						"interface" => "eeprom",
						"size" => 4,
						"type" => "integer"
					}
				},
				"direct_link_deactivate" => {
					"hidden" => true,
					"logical" => {
						"default" => false,
						"type" => "boolean"
					},
					"physical" => {
						"address" => {
							"index" => 0x0006
						},
						"interface" => "eeprom",
						"size" => 0.1,
						"type" => "integer"
					}
				},
				"logging_time" => {
					"conversion" => {
						"factor" => 10,
						"offset" => 0.0,
						"type" => "float_integer_scale"
					},
					"logical" => {
						"default" => 2.0,
						"max" => 25.5,
						"min" => 0.1,
						"type" => "float",
						"unit" => "s"
					},
					"physical" => {
						"address" => {
							"index" => 0x0001
						},
						"interface" => "eeprom",
						"size" => 1.0,
						"type" => "integer"
					}
				}
			},
			"type" => "master"
		},
		'frames' => 	{
			"info_level" => {
				"channel_field" => 10,
				"direction" => "from_device",
				"event" => true,
				"parameter" => {
					"11.0" => {
						"param" => "level",
						"size" => 1.0,
						"type" => "integer"
					},
					"12.4" => {
						"param" => "state_flags",
						"size" => 0.3,
						"type" => "integer"
					}
				},
				"type" => 0x69
			},
			"level_get" => {
				"channel_field" => 10,
				"direction" => "to_device",
				"type" => 0x53
			},
			"level_set" => {
				"channel_field" => 10,
				"direction" => "to_device",
				"parameter" => {
					"index" => 11.0,
					"param" => "level",
					"size" => 1.0,
					"type" => "integer"
				},
				"type" => 0x78
			},
			"stop" => {
				"channel_field" => 10,
				"direction" => "to_device",
				"parameter" => {
					"const_value" => 201,
					"index" => 11.0,
					"size" => 1.0,
					"type" => "integer"
				},
				"type" => 0x78
			}
		},
		'channels' => 	{
			"blind" => {
				"count" => 2,
				"index" => 1,
				"link_roles" => {
					"target" => {
						"name" => "switch"
					}
				},
				"paramset" => {
					"link" => {},
					"master" => {
						"address_start" => 0x07,
						"address_step" => 3,
						"parameter" => {
							"cycle_time" => {
								"conversion" => {
									"factor" => 10,
									"offset" => 0.0,
									"type" => "float_integer_scale"
								},
								"logical" => {
									"default" => 50.0,
									"max" => 6000.0,
									"min" => 0.1,
									"type" => "float",
									"unit" => "s"
								},
								"physical" => {
									"address" => {
										"index" => 1
									},
									"endian" => "little",
									"interface" => "eeprom",
									"size" => 2.0,
									"type" => "integer"
								}
							},
							"logging" => {
								"logical" => {
									"option" => {
										"off" => {},
										"on" => {
											"default" => true
										}
									},
									"type" => "option"
								},
								"physical" => {
									"address" => {
										"index" => 0
									},
									"interface" => "eeprom",
									"size" => 0.1,
									"type" => "integer"
								}
							}
						},
						"type" => "master"
					},
					"values" => {
						"parameter" => {
							"direction" => {
								"conversion" => {
									"type" => "option_integer",
									"value_map" => {
										1 => {
											"device_value" => 0x00,
											"parameter_value" => 0
										},
										2 => {
											"device_value" => 0x01,
											"parameter_value" => 1
										},
										3 => {
											"device_value" => 0x02,
											"parameter_value" => 2
										},
										4 => {
											"device_value" => 0x03,
											"parameter_value" => 3
										}
									}
								},
								"logical" => {
									"option" => {
										"down" => {},
										"none" => {
											"default" => true
										},
										"undefined" => {},
										"up" => {}
									},
									"type" => "option"
								},
								"operations" => "read,event",
								"physical" => {
									"event" => {
										1 => {
											"frame" => "info_level"
										},
										2 => {
											"frame" => "ack_status"
										}
									},
									"get" => {
										"request" => "level_get",
										"response" => "info_level"
									},
									"interface" => "command",
									"type" => "integer",
									"value_id" => "state_flags"
								},
								"ui_flags" => "internal"
							},
							"inhibit" => {
								"control" => "none",
								"logical" => {
									"default" => false,
									"type" => "boolean"
								},
								"loopback" => true,
								"operations" => "read,write,event",
								"physical" => {
									"interface" => "command",
									"set" => {
										"request" => "set_lock"
									},
									"type" => "integer",
									"value_id" => "inhibit"
								}
							},
							"install_test" => {
								"conversion" => {
									"type" => "blind_test",
									"value" => 201
								},
								"logical" => {
									"type" => "action"
								},
								"operations" => "write",
								"physical" => {
									"interface" => "command",
									"no_init" => true,
									"set" => {
										"request" => "toggle_install_test"
									},
									"type" => "integer",
									"value_id" => "toggle_flag"
								},
								"ui_flags" => "internal"
							},
							"level" => {
								"control" => "dimmer.level",
								"conversion" => {
									"factor" => 200,
									"type" => "float_integer_scale"
								},
								"logical" => {
									"default" => 0.0,
									"max" => 1.0,
									"min" => 0.0,
									"type" => "float",
									"unit" => "100%"
								},
								"operations" => "read,write,event",
								"physical" => {
									"event" => {
										"frame" => "info_level"
									},
									"get" => {
										"request" => "level_get",
										"response" => "info_level"
									},
									"interface" => "command",
									"set" => {
										"request" => "level_set"
									},
									"type" => "integer",
									"value_id" => "level"
								}
							},
							"stop" => {
								"control" => "blind.stop",
								"logical" => {
									"type" => "action"
								},
								"operations" => "write",
								"physical" => {
									"interface" => "command",
									"set" => {
										"request" => "stop"
									},
									"type" => "integer",
									"value_id" => "dummy"
								}
							},
							"working" => {
								"conversion" => {
									1 => {
										"type" => "boolean_integer"
									},
									2 => {
										"type" => "integer_integer_map",
										"value_map" => {
											1 => {
												"device_value" => 0x04,
												"mask" => 0x04,
												"parameter_value" => 1
											},
											2 => {
												"device_value" => 0x00,
												"parameter_value" => 0
											},
											3 => {
												"device_value" => 0x01,
												"parameter_value" => 1
											},
											4 => {
												"device_value" => 0x02,
												"parameter_value" => 1
											},
											5 => {
												"device_value" => 0x03,
												"parameter_value" => 0
											}
										}
									}
								},
								"logical" => {
									"default" => false,
									"type" => "boolean"
								},
								"operations" => "read,event",
								"physical" => {
									"event" => {
										1 => {
											"frame" => "info_level"
										},
										2 => {
											"frame" => "ack_status"
										}
									},
									"get" => {
										"request" => "level_get",
										"response" => "info_level"
									},
									"interface" => "command",
									"type" => "integer",
									"value_id" => "state_flags"
								},
								"ui_flags" => "internal"
							}
						},
						"type" => "values"
					}
				},
				"physical_index_offset" => -1
			},
			"maintenance" => {
				"class" => "maintenance",
				"count" => 1,
				"index" => 0,
				"paramset" => {
					"maint_ch_master" => {
						"type" => "master"
					},
					"maint_ch_values" => {
						"parameter" => {
							"config_pending" => {
								"logical" => {
									"type" => "boolean"
								},
								"operations" => "read,event",
								"physical" => {
									"interface" => "internal",
									"type" => "integer",
									"value_id" => "config_pending"
								},
								"ui_flags" => "service"
							},
							"sticky_unreach" => {
								"logical" => {
									"type" => "boolean"
								},
								"operations" => "read,write,event",
								"physical" => {
									"interface" => "internal",
									"type" => "integer",
									"value_id" => "sticky_unreach"
								},
								"ui_flags" => "service"
							},
							"unreach" => {
								"logical" => {
									"type" => "boolean"
								},
								"operations" => "read,event",
								"physical" => {
									"interface" => "internal",
									"type" => "integer",
									"value_id" => "unreach"
								},
								"ui_flags" => "service"
							}
						},
						"type" => "values"
					}
				},
				"ui_flags" => "internal"
			}
		},
	}
);	