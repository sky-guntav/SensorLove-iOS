{
	"patcher" : {
		"fileversion" : 1,
		"appversion" : {
			"major" : 8,
			"minor" : 6,
			"revision" : 0,
			"architecture" : "x64",
			"modernui" : 1
		},
		"classnamespace" : "box",
		"rect" : [ 100.0, 100.0, 720.0, 500.0 ],
		"default_fontsize" : 12.0,
		"default_fontname" : "Arial",
		"gridsize" : [ 15.0, 15.0 ],
		"boxes" : [
			{
				"box" : {
					"id" : "obj-1",
					"maxclass" : "comment",
					"numinlets" : 1,
					"numoutlets" : 0,
					"patching_rect" : [ 20.0, 12.0, 660.0, 20.0 ],
					"text" : "SensorLove in Max: hold the phone up and tilt it. ACCEL's x plays the pitch, its y the volume. Flat is silent."
				}
			},
			{
				"box" : {
					"id" : "obj-2",
					"maxclass" : "comment",
					"numinlets" : 1,
					"numoutlets" : 0,
					"patching_rect" : [ 20.0, 36.0, 680.0, 20.0 ],
					"text" : "SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md."
				}
			},
			{
				"box" : {
					"id" : "obj-3",
					"maxclass" : "newobj",
					"numinlets" : 1,
					"numoutlets" : 1,
					"outlettype" : [ "" ],
					"patching_rect" : [ 20.0, 80.0, 100.0, 22.0 ],
					"text" : "udpreceive 9000"
				}
			},
			{
				"box" : {
					"id" : "obj-4",
					"maxclass" : "newobj",
					"numinlets" : 2,
					"numoutlets" : 3,
					"outlettype" : [ "", "", "" ],
					"patching_rect" : [ 20.0, 115.0, 280.0, 22.0 ],
					"text" : "route /sensorlove/accel/x /sensorlove/accel/y"
				}
			},
			{
				"box" : {
					"id" : "obj-5",
					"maxclass" : "flonum",
					"numinlets" : 1,
					"numoutlets" : 2,
					"outlettype" : [ "", "bang" ],
					"parameter_enable" : 0,
					"patching_rect" : [ 20.0, 150.0, 60.0, 22.0 ]
				}
			},
			{
				"box" : {
					"id" : "obj-6",
					"maxclass" : "flonum",
					"numinlets" : 1,
					"numoutlets" : 2,
					"outlettype" : [ "", "bang" ],
					"parameter_enable" : 0,
					"patching_rect" : [ 160.0, 150.0, 60.0, 22.0 ]
				}
			},
			{
				"box" : {
					"id" : "obj-7",
					"maxclass" : "newobj",
					"numinlets" : 6,
					"numoutlets" : 1,
					"outlettype" : [ "" ],
					"patching_rect" : [ 20.0, 185.0, 120.0, 22.0 ],
					"text" : "scale -1. 1. 48. 72."
				}
			},
			{
				"box" : {
					"id" : "obj-8",
					"maxclass" : "newobj",
					"numinlets" : 1,
					"numoutlets" : 1,
					"outlettype" : [ "" ],
					"patching_rect" : [ 20.0, 220.0, 40.0, 22.0 ],
					"text" : "mtof"
				}
			},
			{
				"box" : {
					"id" : "obj-9",
					"maxclass" : "newobj",
					"numinlets" : 2,
					"numoutlets" : 1,
					"outlettype" : [ "" ],
					"patching_rect" : [ 20.0, 255.0, 70.0, 22.0 ],
					"text" : "pack 0. 30"
				}
			},
			{
				"box" : {
					"id" : "obj-10",
					"maxclass" : "newobj",
					"numinlets" : 2,
					"numoutlets" : 2,
					"outlettype" : [ "signal", "bang" ],
					"patching_rect" : [ 20.0, 290.0, 40.0, 22.0 ],
					"text" : "line~"
				}
			},
			{
				"box" : {
					"id" : "obj-11",
					"maxclass" : "newobj",
					"numinlets" : 2,
					"numoutlets" : 1,
					"outlettype" : [ "signal" ],
					"patching_rect" : [ 20.0, 325.0, 50.0, 22.0 ],
					"text" : "cycle~"
				}
			},
			{
				"box" : {
					"id" : "obj-12",
					"maxclass" : "newobj",
					"numinlets" : 6,
					"numoutlets" : 1,
					"outlettype" : [ "" ],
					"patching_rect" : [ 160.0, 185.0, 120.0, 22.0 ],
					"text" : "scale 0. -1. 0. 0.2"
				}
			},
			{
				"box" : {
					"id" : "obj-13",
					"maxclass" : "newobj",
					"numinlets" : 3,
					"numoutlets" : 1,
					"outlettype" : [ "" ],
					"patching_rect" : [ 160.0, 220.0, 75.0, 22.0 ],
					"text" : "clip 0. 0.2"
				}
			},
			{
				"box" : {
					"id" : "obj-14",
					"maxclass" : "newobj",
					"numinlets" : 2,
					"numoutlets" : 1,
					"outlettype" : [ "" ],
					"patching_rect" : [ 160.0, 255.0, 70.0, 22.0 ],
					"text" : "pack 0. 30"
				}
			},
			{
				"box" : {
					"id" : "obj-15",
					"maxclass" : "newobj",
					"numinlets" : 2,
					"numoutlets" : 2,
					"outlettype" : [ "signal", "bang" ],
					"patching_rect" : [ 160.0, 290.0, 40.0, 22.0 ],
					"text" : "line~"
				}
			},
			{
				"box" : {
					"id" : "obj-16",
					"maxclass" : "newobj",
					"numinlets" : 2,
					"numoutlets" : 1,
					"outlettype" : [ "signal" ],
					"patching_rect" : [ 20.0, 370.0, 40.0, 22.0 ],
					"text" : "*~"
				}
			},
			{
				"box" : {
					"id" : "obj-17",
					"maxclass" : "ezdac~",
					"numinlets" : 2,
					"numoutlets" : 0,
					"patching_rect" : [ 20.0, 410.0, 45.0, 45.0 ]
				}
			},
			{
				"box" : {
					"id" : "obj-18",
					"maxclass" : "comment",
					"numinlets" : 1,
					"numoutlets" : 0,
					"patching_rect" : [ 80.0, 422.0, 300.0, 20.0 ],
					"text" : "Click the speaker to turn audio on."
				}
			}
		],
		"lines" : [
			{ "patchline" : { "source" : [ "obj-3", 0 ], "destination" : [ "obj-4", 0 ] } },
			{ "patchline" : { "source" : [ "obj-4", 0 ], "destination" : [ "obj-5", 0 ] } },
			{ "patchline" : { "source" : [ "obj-4", 1 ], "destination" : [ "obj-6", 0 ] } },
			{ "patchline" : { "source" : [ "obj-5", 0 ], "destination" : [ "obj-7", 0 ] } },
			{ "patchline" : { "source" : [ "obj-7", 0 ], "destination" : [ "obj-8", 0 ] } },
			{ "patchline" : { "source" : [ "obj-8", 0 ], "destination" : [ "obj-9", 0 ] } },
			{ "patchline" : { "source" : [ "obj-9", 0 ], "destination" : [ "obj-10", 0 ] } },
			{ "patchline" : { "source" : [ "obj-10", 0 ], "destination" : [ "obj-11", 0 ] } },
			{ "patchline" : { "source" : [ "obj-11", 0 ], "destination" : [ "obj-16", 0 ] } },
			{ "patchline" : { "source" : [ "obj-6", 0 ], "destination" : [ "obj-12", 0 ] } },
			{ "patchline" : { "source" : [ "obj-12", 0 ], "destination" : [ "obj-13", 0 ] } },
			{ "patchline" : { "source" : [ "obj-13", 0 ], "destination" : [ "obj-14", 0 ] } },
			{ "patchline" : { "source" : [ "obj-14", 0 ], "destination" : [ "obj-15", 0 ] } },
			{ "patchline" : { "source" : [ "obj-15", 0 ], "destination" : [ "obj-16", 1 ] } },
			{ "patchline" : { "source" : [ "obj-16", 0 ], "destination" : [ "obj-17", 0 ] } },
			{ "patchline" : { "source" : [ "obj-16", 0 ], "destination" : [ "obj-17", 1 ] } }
		]
	}
}
