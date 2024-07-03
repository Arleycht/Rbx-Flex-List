The `FlexList.luau` script can be used as a drop-in replacement as-is, or you
can enable the beta feature in Roblox Studio and put the script alongside any
`UIListLayout` element to implement flex boxes in the client-side.

This script has a side benefit of being moddable, even if the feature becomes
officially available to the client.

This repository additionally contains a helper script that can be placed in the
highest level parent in the tree of a `ScreenGui` or something similar (with a
copy of the script as a child) to automatically replace all descendant
`UIListLayout`s with the custom script.

This script is not guaranteed to produce exactly identical results as the
official beta implementation as it is closed source, however I tried to mimic it
as closely as possible so that it is useful for producing flexible UI.
