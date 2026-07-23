'    CComboBox - reusable owner-drawn dropdown selector control
'    Copyright (C) 2016-2026 Paul Squires, PlanetSquires Software
'
'    This program is free software: you can redistribute it and/or modify
'    it under the terms of the GNU General Public License as published by
'    the Free Software Foundation, either version 3 of the License, or
'    (at your option) any later version.
'
'    This program is distributed in the hope that it will be useful,
'    but WITHOUT any WARRANTY; without even the implied warranty of
'    MERCHANTABILITY or FITNESS for A PARTICULAR PURPOSE.  See the
'    GNU General Public License for more details.

#pragma once

' The demo lays the comboboxes out as a settings pane: one per row, label on the left,
' control on the right -- the arrangement the control was drawn for.
'
'   0  the reference screenshot, reproduced: two items, the longer one selected
'   1  ARROW-ONLY mode (no caption; the width collapses to padding + chevron)
'   2  DISABLED, with a selection, so the greyed state is visible
'   3  NO SELECTION (-1) with a placeholder string
'   4  a MUTABLE list, driven by the two buttons below, exercising the index fix-up
'   5  a custom PAINT CALLBACK replacing the built-in painter wholesale
#define COMBO_COUNT   6

#define IDC_FRMMAIN_COMBO_FIRST    1000
#define IDC_FRMMAIN_BTN_ADD        1100
#define IDC_FRMMAIN_BTN_DELETE     1101
#define IDC_FRMMAIN_BTN_AUTOSIZE   1102

' The mutable row -- the one the Add/Delete buttons act on.
#define COMBO_MUTABLE   4

declare function frmMain_Show( byval hWndParent as HWND ) as LRESULT
