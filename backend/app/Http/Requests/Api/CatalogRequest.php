<?php

namespace App\Http\Requests\Api;

use Illuminate\Foundation\Http\FormRequest;

class CatalogRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            // ISO 8601, mis. 2026-10-08T10:00:00Z. Kosong = sinkronisasi penuh.
            'updated_since' => ['nullable', 'date'],
        ];
    }

    public function messages(): array
    {
        return ['updated_since.date' => 'Format updated_since tidak valid.'];
    }
}
