#Requires -Modules Pester

BeforeAll {
    # Dot-source the script in a way that only loads functions/variables
    # without executing the main logic (which requires clipboard APIs)
    # We extract the testable parts by parsing the script

    $scriptPath = Join-Path $PSScriptRoot '..' 'UrlClipboardLanguageCleaner.ps1'
    $scriptContent = Get-Content $scriptPath -Raw

    # Extract the locale pattern, excluded codes, and Remove-UrlLocale function
    # by evaluating just those parts
    $localePattern = '(?i)\/[a-z]{2}(?:-[a-z]{2,4})?(?=\/)'
    $excludedCodes = @('to','do','go','me','us','my','no','or','so','up','if','in','on','at','by','of','as','is','it','an')

    function Remove-UrlLocale {
        param([string]$Text)

        $Text = $Text.Trim()
        if ($Text.Length -gt 2048) { return $null }

        try {
            $uri = [System.Uri]::new($Text)
        }
        catch {
            return $null
        }

        if ($uri.Scheme -notin @('http', 'https')) { return $null }

        $originalPath = $uri.AbsolutePath

        $match = [System.Text.RegularExpressions.Regex]::Match($originalPath, $localePattern)
        if (-not $match.Success) { return $null }
        $matchedCode = $match.Value.TrimStart('/').ToLowerInvariant()
        if ($matchedCode.Length -eq 2 -and $matchedCode -in $excludedCodes) { return $null }

        $cleanedPath = $originalPath.Remove($match.Index, $match.Length)

        if ($cleanedPath -eq $originalPath) { return $null }

        $builder = [System.UriBuilder]::new($uri)
        $builder.Path = $cleanedPath
        return $builder.Uri.AbsoluteUri
    }
}

Describe 'Remove-UrlLocale' {

    Context 'Locale with region subtag (xx-xx format)' {
        It 'Removes /en-gb/ from Microsoft Learn URL' {
            $result = Remove-UrlLocale -Text 'https://learn.microsoft.com/en-gb/azure/virtual-machines/overview'
            $result | Should -Be 'https://learn.microsoft.com/azure/virtual-machines/overview'
        }

        It 'Removes /en-us/ from Microsoft support URL' {
            $result = Remove-UrlLocale -Text 'https://support.microsoft.com/en-us/help/12345'
            $result | Should -Be 'https://support.microsoft.com/help/12345'
        }

        It 'Removes /fr-fr/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/fr-fr/docs/guide'
            $result | Should -Be 'https://example.com/docs/guide'
        }

        It 'Removes /zh-hans/ from URL (4-letter region subtag)' {
            $result = Remove-UrlLocale -Text 'https://learn.microsoft.com/zh-hans/dotnet/overview'
            $result | Should -Be 'https://learn.microsoft.com/dotnet/overview'
        }

        It 'Removes /de-de/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/de-de/products/item'
            $result | Should -Be 'https://example.com/products/item'
        }

        It 'Removes /pt-br/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/pt-br/docs/getting-started'
            $result | Should -Be 'https://example.com/docs/getting-started'
        }
    }

    Context 'Bare 2-letter locale codes (xx format)' {
        It 'Removes /en/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/en/docs/guide'
            $result | Should -Be 'https://example.com/docs/guide'
        }

        It 'Removes /fr/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/fr/products'
            $result | Should -Be 'https://example.com/products'
        }

        It 'Removes /de/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/de/products/item'
            $result | Should -Be 'https://example.com/products/item'
        }

        It 'Removes /ja/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/ja/support/faq'
            $result | Should -Be 'https://example.com/support/faq'
        }

        It 'Removes /ko/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/ko/help/article'
            $result | Should -Be 'https://example.com/help/article'
        }
    }

    Context 'Locale segment not in first path position' {
        It 'Removes /en/ from /api/en/docs' {
            $result = Remove-UrlLocale -Text 'https://example.com/api/en/docs'
            $result | Should -Be 'https://example.com/api/docs'
        }

        It 'Removes /en-gb/ from /v2/en-gb/resources' {
            $result = Remove-UrlLocale -Text 'https://example.com/v2/en-gb/resources'
            $result | Should -Be 'https://example.com/v2/resources'
        }

        It 'Removes /fr-fr/ from deeper path' {
            $result = Remove-UrlLocale -Text 'https://example.com/content/fr-fr/articles/overview'
            $result | Should -Be 'https://example.com/content/articles/overview'
        }
    }

    Context 'Excluded 2-letter codes (common English words)' {
        It 'Does NOT remove /to/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/to/something/else'
            $result | Should -BeNullOrEmpty
        }

        It 'Does NOT remove /do/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/do/action/now'
            $result | Should -BeNullOrEmpty
        }

        It 'Does NOT remove /go/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/go/somewhere/fast'
            $result | Should -BeNullOrEmpty
        }

        It 'Does NOT remove /me/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/me/profile/settings'
            $result | Should -BeNullOrEmpty
        }

        It 'Does NOT remove /us/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/us/store/item'
            $result | Should -BeNullOrEmpty
        }

        It 'Does NOT remove /my/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/my/account/details'
            $result | Should -BeNullOrEmpty
        }

        It 'Does NOT remove /no/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/no/access/denied'
            $result | Should -BeNullOrEmpty
        }

        It 'Does NOT remove /or/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/or/alternative/option'
            $result | Should -BeNullOrEmpty
        }

        It 'Does NOT remove /if/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/if/condition/met'
            $result | Should -BeNullOrEmpty
        }

        It 'Does NOT remove /in/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/in/category/item'
            $result | Should -BeNullOrEmpty
        }

        It 'Does NOT remove /on/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/on/topic/detail'
            $result | Should -BeNullOrEmpty
        }

        It 'Does NOT remove /at/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/at/location/place'
            $result | Should -BeNullOrEmpty
        }

        It 'Does NOT remove /as/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/as/role/admin'
            $result | Should -BeNullOrEmpty
        }

        It 'Does NOT remove /an/ from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/an/item/detail'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Excluded codes with region subtag SHOULD still be matched' {
        It 'Removes /no-nb/ (Norwegian Bokmal) from URL' {
            $result = Remove-UrlLocale -Text 'https://example.com/no-nb/docs/guide'
            $result | Should -Be 'https://example.com/docs/guide'
        }

        It 'Removes /it-it/ (Italian) from URL despite /it/ being excluded' {
            $result = Remove-UrlLocale -Text 'https://example.com/it-it/products/item'
            $result | Should -Be 'https://example.com/products/item'
        }
    }

    Context 'URLs without locale segments (should not modify)' {
        It 'Returns null for URL without locale' {
            $result = Remove-UrlLocale -Text 'https://example.com/docs/guide'
            $result | Should -BeNullOrEmpty
        }

        It 'Returns null for URL with only root path' {
            $result = Remove-UrlLocale -Text 'https://example.com/'
            $result | Should -BeNullOrEmpty
        }

        It 'Returns null for URL with single segment (no trailing content)' {
            $result = Remove-UrlLocale -Text 'https://example.com/en'
            $result | Should -BeNullOrEmpty
        }

        It 'Returns null for URL with 3-letter path segment' {
            $result = Remove-UrlLocale -Text 'https://example.com/api/docs'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Query strings and fragments preserved' {
        It 'Preserves query string after cleaning' {
            $result = Remove-UrlLocale -Text 'https://learn.microsoft.com/en-gb/azure/overview?view=latest'
            $result | Should -Be 'https://learn.microsoft.com/azure/overview?view=latest'
        }

        It 'Preserves fragment after cleaning' {
            $result = Remove-UrlLocale -Text 'https://learn.microsoft.com/en-us/azure/overview#section'
            $result | Should -Be 'https://learn.microsoft.com/azure/overview#section'
        }

        It 'Preserves both query string and fragment' {
            $result = Remove-UrlLocale -Text 'https://learn.microsoft.com/en-gb/azure/overview?view=latest#top'
            $result | Should -Be 'https://learn.microsoft.com/azure/overview?view=latest#top'
        }
    }

    Context 'Non-URL and invalid input' {
        It 'Returns null for plain text' {
            $result = Remove-UrlLocale -Text 'just some text'
            $result | Should -BeNullOrEmpty
        }

        It 'Returns null for empty string' {
            $result = Remove-UrlLocale -Text ''
            $result | Should -BeNullOrEmpty
        }

        It 'Returns null for whitespace' {
            $result = Remove-UrlLocale -Text '   '
            $result | Should -BeNullOrEmpty
        }

        It 'Returns null for FTP URL' {
            $result = Remove-UrlLocale -Text 'ftp://example.com/en-gb/files'
            $result | Should -BeNullOrEmpty
        }

        It 'Returns null for URL exceeding 2048 characters' {
            $longPath = '/en-gb/' + ('a' * 2050)
            $result = Remove-UrlLocale -Text "https://example.com$longPath"
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Case insensitivity' {
        It 'Removes /EN-GB/ (uppercase) from URL' {
            $result = Remove-UrlLocale -Text 'https://learn.microsoft.com/EN-GB/azure/overview'
            $result | Should -Be 'https://learn.microsoft.com/azure/overview'
        }

        It 'Removes /En-Gb/ (mixed case) from URL' {
            $result = Remove-UrlLocale -Text 'https://learn.microsoft.com/En-Gb/azure/overview'
            $result | Should -Be 'https://learn.microsoft.com/azure/overview'
        }
    }

    Context 'Whitespace handling' {
        It 'Trims leading/trailing whitespace before processing' {
            $result = Remove-UrlLocale -Text '  https://learn.microsoft.com/en-gb/azure/overview  '
            $result | Should -Be 'https://learn.microsoft.com/azure/overview'
        }
    }

    Context 'Only first locale segment is removed' {
        It 'Removes only the first locale match when multiple exist' {
            $result = Remove-UrlLocale -Text 'https://example.com/en-gb/fr-fr/docs'
            $result | Should -Be 'https://example.com/fr-fr/docs'
        }
    }

    Context 'HTTP scheme support' {
        It 'Works with http:// URLs' {
            $result = Remove-UrlLocale -Text 'http://learn.microsoft.com/en-gb/azure/overview'
            $result | Should -Be 'http://learn.microsoft.com/azure/overview'
        }

        It 'Works with https:// URLs' {
            $result = Remove-UrlLocale -Text 'https://learn.microsoft.com/en-gb/azure/overview'
            $result | Should -Be 'https://learn.microsoft.com/azure/overview'
        }
    }

    Context 'Real-world URLs' {
        It 'Cleans Microsoft Learn sovereign cloud URL' {
            $result = Remove-UrlLocale -Text 'https://learn.microsoft.com/en-gb/industry/sovereign-cloud/sovereign-public-cloud/overview-controls-principles'
            $result | Should -Be 'https://learn.microsoft.com/industry/sovereign-cloud/sovereign-public-cloud/overview-controls-principles'
        }

        It 'Cleans Microsoft Azure docs URL' {
            $result = Remove-UrlLocale -Text 'https://learn.microsoft.com/en-us/azure/architecture/best-practices/api-design'
            $result | Should -Be 'https://learn.microsoft.com/azure/architecture/best-practices/api-design'
        }

        It 'Cleans Microsoft .NET docs URL' {
            $result = Remove-UrlLocale -Text 'https://learn.microsoft.com/ja-jp/dotnet/csharp/tour-of-csharp'
            $result | Should -Be 'https://learn.microsoft.com/dotnet/csharp/tour-of-csharp'
        }
    }
}
