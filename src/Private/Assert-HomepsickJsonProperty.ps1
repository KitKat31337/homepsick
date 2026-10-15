function Assert-HomepsickJsonProperty {
    # Reject duplicate JSON keys recursively before hashtable conversion can hide them.
    # Names are case-insensitive, matching PowerShell property access. Emits nothing;
    # throws on a duplicate so the parser can return an InvalidJson diagnostic.
    param([System.Text.Json.JsonElement]$Element)
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw "Duplicate JSON property '$($property.Name)'." }
            Assert-HomepsickJsonProperty $property.Value
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-HomepsickJsonProperty $item }
    }
}
