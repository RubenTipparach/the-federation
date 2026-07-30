extends Node2D

## Build pipeline smoke test.
##
## PLACEHOLDER. This exists only so a deployed build can be verified by looking
## at it: a blank window cannot distinguish a correct deploy from a broken one.
## M1 in docs/07-roadmap.md replaces this entire scene with the tactical
## prototype, and any real UI needs mockup approval first per CLAUDE.md
## section 6.
##
## Written in GDScript rather than C# deliberately. The client language is still
## an open decision (see docs/08-build-and-deploy.md section 6, where the C#
## choice appears to rule out Web export), so this avoids adding a .csproj and a
## NuGet dependency to the pipeline before that is settled. The .NET flavor of
## Godot is still exercised by the build: the export crashes without the SDK.

## Printed to stdout as well as shown on screen. scripts/verify-build.sh greps
## for this marker to prove an exported binary actually boots and runs its
## scripts, which cannot be checked by looking at a headless window.
const SMOKE_MARKER := "FEDERATION_SMOKE_OK"

const REPORT_LINES := [
	"THE FEDERATION",
	"",
	"Build pipeline smoke test. No gameplay here yet.",
]


func _ready() -> void:
	var report := "\n".join(REPORT_LINES + _environment_report())

	var label := get_node_or_null("BuildInfo") as Label
	if label == null:
		push_error("BuildInfo label missing from main.tscn")
	else:
		label.text = report

	# Emitted last, so seeing the marker means everything above it succeeded.
	print(report)
	print(SMOKE_MARKER)


## Facts read from the engine at runtime, so nothing has to be stamped into a
## committed file at build time. Together these identify which build is running
## and confirm the export targeted the platform it was supposed to.
func _environment_report() -> Array[String]:
	return [
		"",
		"Engine:    %s" % Engine.get_version_info().get("string", "unknown"),
		"Platform:  %s" % OS.get_name(),
		"Renderer:  %s" % RenderingServer.get_video_adapter_name(),
		"Debug:     %s" % ("yes" if OS.is_debug_build() else "no"),
	]
