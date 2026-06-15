# Noted. — Product Requirements Document (PRD) dan Kerangka Desain

## 1. Ringkasan Produk

**Noted.** adalah aplikasi mobile note taking yang dirancang untuk membantu mahasiswa mencatat materi kuliah, mengelompokkan catatan berdasarkan mata kuliah, menandai catatan penting, dan mencari catatan dengan cepat.

Aplikasi ini ditujukan untuk mahasiswa yang membutuhkan media pencatatan sederhana, rapi, dan mudah digunakan dalam kegiatan perkuliahan sehari-hari.

---

## 2. Latar Belakang

Mahasiswa sering mencatat materi kuliah di berbagai tempat, seperti buku, aplikasi chat, dokumen, atau notes bawaan perangkat. Hal ini membuat catatan menjadi tersebar, sulit dicari kembali, dan tidak terorganisir berdasarkan mata kuliah.

Oleh karena itu, dibutuhkan aplikasi pencatatan yang sederhana namun tetap terstruktur agar mahasiswa dapat menyimpan dan mengelola catatan akademik dengan lebih mudah.

Noted. dibuat sebagai solusi pencatatan digital untuk mahasiswa dengan fitur yang fokus pada kebutuhan akademik, seperti kategori mata kuliah, pencarian catatan, dan penanda catatan penting.

---

## 3. Tujuan Produk

Tujuan dari aplikasi Noted. adalah:

1. Membantu mahasiswa mencatat materi kuliah secara digital.
2. Mempermudah pengelompokan catatan berdasarkan mata kuliah.
3. Memudahkan pencarian catatan lama.
4. Memberikan fitur penanda untuk catatan penting.
5. Menyediakan sistem akun agar catatan setiap pengguna tersimpan secara personal.
6. Mengimplementasikan konsep CRUD, autentikasi, database network, MVVM, dan state management dalam aplikasi mobile.

---

## 4. Target Pengguna

Target pengguna utama aplikasi ini adalah:

- Mahasiswa aktif
- Pelajar
- Pengguna yang membutuhkan aplikasi catatan sederhana
- Pengguna yang ingin mengelompokkan catatan berdasarkan kategori tertentu

---

## 5. Masalah Pengguna

Beberapa masalah yang ingin diselesaikan oleh aplikasi ini:

1. Catatan kuliah sering tersebar di banyak tempat.
2. Catatan sulit ditemukan kembali ketika dibutuhkan.
3. Mahasiswa kesulitan membedakan catatan biasa dan catatan penting.
4. Catatan tidak terorganisir berdasarkan mata kuliah.
5. Pengguna membutuhkan aplikasi pencatatan yang simpel dan tidak serumit aplikasi seperti Notion.

---

## 6. Solusi yang Ditawarkan

Noted. menyediakan aplikasi pencatatan yang sederhana dengan fitur utama:

1. Login dan register akun.
2. Dashboard yang menampilkan informasi pengguna aktif.
3. Tambah, lihat, edit, dan hapus catatan.
4. Kategori catatan berdasarkan mata kuliah.
5. Penanda catatan penting atau favorite.
6. Pencarian catatan berdasarkan judul atau isi.
7. Profil pengguna dan fitur logout.

---

## 7. Fitur Utama

### 7.1 Sign Up

Pengguna dapat membuat akun baru menggunakan email, password, dan nama pengguna.

**Input:**

- Nama
- Email
- Password

**Output:**

- Akun pengguna berhasil dibuat
- Data pengguna tersimpan ke database
- Pengguna diarahkan ke halaman Home

---

### 7.2 Sign In

Pengguna dapat masuk ke aplikasi menggunakan email dan password.

**Input:**

- Email
- Password

**Output:**

- Pengguna berhasil masuk
- Aplikasi menampilkan data user aktif
- Pengguna diarahkan ke halaman Home

---

### 7.3 Dashboard

Dashboard menampilkan ringkasan data pengguna dan catatan.

**Isi halaman:**

- Sapaan pengguna aktif
- Total catatan
- Total catatan favorite
- Catatan terbaru
- Tombol tambah catatan

---

### 7.4 Notes List

Halaman ini menampilkan semua catatan milik pengguna.

**Fitur:**

- Menampilkan daftar catatan
- Search catatan
- Filter berdasarkan kategori
- Menampilkan status favorite
- Navigasi ke detail catatan

---

### 7.5 Add Note

Pengguna dapat menambahkan catatan baru.

**Input:**

- Judul catatan
- Isi catatan
- Kategori/mata kuliah
- Status favorite

**Output:**

- Catatan tersimpan ke database
- Catatan muncul di halaman Notes List

---

### 7.6 Edit Note

Pengguna dapat mengubah catatan yang sudah dibuat.

**Input:**

- Judul baru
- Isi baru
- Kategori baru
- Status favorite

**Output:**

- Data catatan diperbarui di database

---

### 7.7 Delete Note

Pengguna dapat menghapus catatan.

**Output:**

- Catatan dihapus dari database
- Catatan tidak lagi muncul di daftar catatan

---

### 7.8 Note Detail

Halaman ini menampilkan informasi lengkap dari sebuah catatan.

**Isi halaman:**

- Judul catatan
- Isi catatan
- Kategori
- Tanggal dibuat
- Tanggal diperbarui
- Status favorite
- Tombol edit
- Tombol delete

---

### 7.9 Profile

Halaman profil menampilkan data user aktif.

**Isi halaman:**

- Nama pengguna
- Email pengguna
- Jumlah catatan
- Tombol logout

---

## 8. Fitur MVP

Fitur yang wajib dibuat terlebih dahulu:

1. Sign Up
2. Sign In
3. Menampilkan user aktif
4. CRUD catatan
5. Kategori catatan
6. Favorite note
7. Search note
8. Profile dan logout

Fitur tambahan seperti dark mode, reminder, atau upload gambar dapat ditambahkan jika fitur utama sudah selesai.

---

## 9. Halaman Aplikasi

Minimal halaman yang dibuat:

1. Splash / Welcome Page
2. Sign In Page
3. Sign Up Page
4. Home / Dashboard Page
5. Notes List Page
6. Add/Edit Note Page
7. Note Detail Page
8. Favorites Page
9. Profile Page

Dengan struktur ini, aplikasi sudah memiliki lebih dari 5 halaman UI.

---

## 10. User Flow

### 10.1 Flow Registrasi

```text
User membuka aplikasi
→ Welcome Page
→ Sign Up
→ Mengisi nama, email, password
→ Akun dibuat
→ Masuk ke Home Page
```

### 10.2 Flow Login

```text
User membuka aplikasi
→ Welcome Page
→ Sign In
→ Mengisi email dan password
→ Login berhasil
→ Masuk ke Home Page
```

### 10.3 Flow Membuat Catatan

```text
Home Page
→ Klik tombol tambah catatan
→ Isi judul, isi, dan kategori
→ Klik Save
→ Catatan tersimpan
→ Kembali ke Notes List
```

### 10.4 Flow Mengedit Catatan

```text
Notes List
→ Pilih catatan
→ Note Detail
→ Klik Edit
→ Ubah data catatan
→ Klik Save
→ Data diperbarui
```

### 10.5 Flow Menghapus Catatan

```text
Notes List
→ Pilih catatan
→ Note Detail
→ Klik Delete
→ Konfirmasi hapus
→ Catatan terhapus
```

---

## 11. Struktur Database

Database yang disarankan: **Firebase Firestore**.

### Collection: `users`

| Field | Tipe Data | Keterangan |
|---|---|---|
| `uid` | String | ID unik user |
| `name` | String | Nama pengguna |
| `email` | String | Email pengguna |
| `createdAt` | Timestamp | Tanggal akun dibuat |

### Collection: `notes`

| Field | Tipe Data | Keterangan |
|---|---|---|
| `noteId` | String | ID unik catatan |
| `userId` | String | ID pemilik catatan |
| `title` | String | Judul catatan |
| `content` | String | Isi catatan |
| `category` | String | Kategori/mata kuliah |
| `isFavorite` | Boolean | Status favorite |
| `createdAt` | Timestamp | Tanggal catatan dibuat |
| `updatedAt` | Timestamp | Tanggal catatan diperbarui |

---

## 12. Teknologi yang Digunakan

Aplikasi dapat dikembangkan menggunakan:

- Flutter
- Firebase Authentication
- Cloud Firestore
- Provider untuk State Management
- MVVM Architecture
- Android Studio atau Visual Studio Code
- GitHub untuk repository project

---

## 13. Arsitektur MVVM

Aplikasi menggunakan arsitektur **Model-View-ViewModel**.

### 13.1 Model

Berisi struktur data aplikasi.

Contoh:

- `UserModel`
- `NoteModel`

### 13.2 View

Berisi tampilan UI aplikasi.

Contoh:

- `WelcomePage`
- `SignInPage`
- `SignUpPage`
- `HomePage`
- `NotesPage`
- `AddEditNotePage`
- `NoteDetailPage`
- `FavoritesPage`
- `ProfilePage`

### 13.3 ViewModel

Berisi logic yang menghubungkan View dengan Repository.

Contoh:

- `AuthViewModel`
- `NoteViewModel`

### 13.4 Repository

Berisi komunikasi dengan Firebase.

Contoh:

- `AuthRepository`
- `NoteRepository`

---

## 14. State Management

State management digunakan untuk mengatur perubahan data pada aplikasi, seperti:

1. Status login pengguna.
2. Data user aktif.
3. Daftar catatan.
4. Status loading ketika mengambil data.
5. Proses tambah, edit, dan hapus catatan.
6. Proses pencarian dan filter catatan.

State management yang disarankan adalah **Provider** karena lebih sederhana untuk project mahasiswa dan mudah dijelaskan saat presentasi.

---

## 15. Kriteria Keberhasilan

Aplikasi dianggap berhasil apabila:

1. User dapat melakukan sign up.
2. User dapat melakukan sign in.
3. Aplikasi dapat menampilkan user aktif.
4. User dapat menambah catatan.
5. User dapat melihat daftar catatan.
6. User dapat mengedit catatan.
7. User dapat menghapus catatan.
8. User dapat mencari catatan.
9. User dapat menandai catatan sebagai favorite.
10. Data tersimpan di database network.
11. Aplikasi menerapkan MVVM dan state management.
12. APK berhasil dibuat.

---

# Kerangka Desain Aplikasi

## 1. Konsep Visual

**Tema desain:**  
Clean, modern, soft academic productivity app.

Aplikasi sebaiknya menggunakan desain yang sederhana, rapi, dan nyaman dilihat. Fokus utama UI adalah memudahkan user membaca dan mengelola catatan.

---

## 2. Warna Desain

| Elemen | Warna |
|---|---|
| Background | Off-white / `#F8F7F2` |
| Primary | Sage Green / `#6A9C89` |
| Secondary | Soft Yellow / `#FFD66B` |
| Text utama | Dark Gray / `#2F2F2F` |
| Card | White / `#FFFFFF` |
| Delete/Error | Soft Red / `#E57373` |

---

## 3. Struktur Navigasi

Setelah user login, aplikasi menggunakan **Bottom Navigation Bar**.

Menu utama:

1. Home
2. Notes
3. Favorites
4. Profile

Struktur navigasi:

```text
Welcome
├── Sign In
└── Sign Up
    ↓
Main Layout
├── Home
├── Notes
│   ├── Note Detail
│   └── Add/Edit Note
├── Favorites
└── Profile
```

---

## 4. Kerangka UI Per Halaman

## 4.1 Welcome Page

**Fungsi:**  
Halaman pembuka aplikasi.

**Isi halaman:**

- Logo aplikasi
- Nama aplikasi: Noted.
- Tagline: "Organize your study notes easily"
- Tombol Sign In
- Tombol Sign Up

**Wireframe sederhana:**

```text
+-----------------------------+
|                             |
|          [ Logo ]            |
|                             |
|        Noted.             |
| Organize your study notes    |
|          easily              |
|                             |
|      [ Sign In ]             |
|      [ Sign Up ]             |
|                             |
+-----------------------------+
```

---

## 4.2 Sign In Page

**Isi halaman:**

- Judul: "Welcome Back"
- Text field email
- Text field password
- Tombol Sign In
- Link ke Sign Up

**Wireframe sederhana:**

```text
+-----------------------------+
| Welcome Back                |
| Login to your account       |
|                             |
| Email                       |
| [____________________]      |
|                             |
| Password                    |
| [____________________]      |
|                             |
| [ Sign In ]                 |
|                             |
| Don't have an account?      |
| Sign Up                     |
+-----------------------------+
```

---

## 4.3 Sign Up Page

**Isi halaman:**

- Judul: "Create Account"
- Text field name
- Text field email
- Text field password
- Tombol Sign Up
- Link ke Sign In

**Wireframe sederhana:**

```text
+-----------------------------+
| Create Account              |
| Start organizing your notes |
|                             |
| Name                        |
| [____________________]      |
|                             |
| Email                       |
| [____________________]      |
|                             |
| Password                    |
| [____________________]      |
|                             |
| [ Sign Up ]                 |
|                             |
| Already have an account?    |
| Sign In                     |
+-----------------------------+
```

---

## 4.4 Home / Dashboard Page

**Isi halaman:**

- Sapaan user aktif
- Total notes
- Total favorite notes
- Recent notes
- Floating action button untuk tambah catatan

**Wireframe sederhana:**

```text
+-----------------------------+
| Hello, Diaz 👋              |
| Let's organize your notes   |
|                             |
| [ Total Notes: 12 ]         |
| [ Favorites: 3    ]         |
|                             |
| Recent Notes                |
| +-------------------------+ |
| | Mobile Programming      | |
| | State Management...     | |
| +-------------------------+ |
| +-------------------------+ |
| | Database System         | |
| | SQL Join notes...       | |
| +-------------------------+ |
|                             |
|                    [ + ]    |
+-----------------------------+
```

---

## 4.5 Notes List Page

**Isi halaman:**

- Search bar
- Filter kategori
- List catatan
- Tombol tambah catatan

**Card catatan berisi:**

- Judul
- Potongan isi catatan
- Kategori
- Tanggal
- Icon favorite

**Wireframe sederhana:**

```text
+-----------------------------+
| Notes                       |
| [ Search your notes... ]    |
|                             |
| [All] [Mobile] [Database]   |
|                             |
| +-------------------------+ |
| | Mobile Programming    ★ | |
| | State Management in...  | |
| | #Mobile Programming     | |
| +-------------------------+ |
|                             |
| +-------------------------+ |
| | Database System       ☆ | |
| | Normalization notes...  | |
| | #Database               | |
| +-------------------------+ |
+-----------------------------+
```

---

## 4.6 Add/Edit Note Page

**Isi halaman:**

- Text field judul
- Dropdown kategori
- Text area isi catatan
- Switch favorite
- Tombol Save

**Wireframe sederhana:**

```text
+-----------------------------+
| Add Note                    |
|                             |
| Title                       |
| [____________________]      |
|                             |
| Category                    |
| [ Select Category    v ]    |
|                             |
| Content                     |
| +-------------------------+ |
| |                         | |
| | Write your note here... | |
| |                         | |
| +-------------------------+ |
|                             |
| Favorite [ switch ]         |
|                             |
| [ Save Note ]               |
+-----------------------------+
```

---

## 4.7 Note Detail Page

**Isi halaman:**

- Judul catatan
- Kategori
- Tanggal dibuat
- Isi lengkap catatan
- Tombol edit
- Tombol delete
- Tombol favorite

**Wireframe sederhana:**

```text
+-----------------------------+
| < Note Detail            ★  |
|                             |
| Mobile Programming          |
| #Mobile Programming         |
| Created: 14 June 2026       |
|                             |
| State management is used    |
| to manage application       |
| state and update UI...      |
|                             |
| [ Edit ]     [ Delete ]     |
+-----------------------------+
```

---

## 4.8 Favorites Page

**Isi halaman:**

- Daftar catatan favorite
- Empty state jika belum ada favorite

**Wireframe sederhana:**

```text
+-----------------------------+
| Favorites                   |
|                             |
| +-------------------------+ |
| | Mobile Programming    ★ | |
| | State Management in...  | |
| +-------------------------+ |
|                             |
| +-------------------------+ |
| | Project Management    ★ | |
| | Risk management notes...| |
| +-------------------------+ |
+-----------------------------+
```

**Empty state:**

```text
No favorite notes yet.
Mark important notes as favorite to find them faster.
```

---

## 4.9 Profile Page

**Isi halaman:**

- Nama user aktif
- Email user
- Total notes
- Total favorite notes
- Tombol logout

**Wireframe sederhana:**

```text
+-----------------------------+
| Profile                     |
|                             |
|       [ User Icon ]          |
| Diaz Hylmi Lutfiazka        |
| diaz@email.com              |
|                             |
| Total Notes: 12             |
| Favorite Notes: 3           |
|                             |
| [ Logout ]                  |
+-----------------------------+
```

---

# Struktur Folder Flutter

```text
lib/
├── main.dart
├── app.dart
├── models/
│   ├── user_model.dart
│   └── note_model.dart
├── views/
│   ├── welcome_page.dart
│   ├── sign_in_page.dart
│   ├── sign_up_page.dart
│   ├── home_page.dart
│   ├── notes_page.dart
│   ├── add_edit_note_page.dart
│   ├── note_detail_page.dart
│   ├── favorites_page.dart
│   └── profile_page.dart
├── viewmodels/
│   ├── auth_viewmodel.dart
│   └── note_viewmodel.dart
├── repositories/
│   ├── auth_repository.dart
│   └── note_repository.dart
├── services/
│   └── firebase_service.dart
├── widgets/
│   ├── note_card.dart
│   ├── custom_button.dart
│   ├── custom_text_field.dart
│   └── empty_state.dart
└── utils/
    ├── app_colors.dart
    └── app_routes.dart
```

---

# Rekomendasi Fitur Final

Fitur final yang disarankan:

| Fitur | Prioritas | Alasan |
|---|---:|---|
| Sign In & Sign Up | Wajib | Sesuai requirement |
| User aktif | Wajib | Sesuai requirement |
| CRUD Notes | Wajib | Inti aplikasi |
| Firebase Firestore | Wajib | Database network |
| MVVM | Wajib | Sesuai requirement |
| Provider | Wajib | State management |
| Search Notes | Tinggi | Menarik tapi tidak rumit |
| Category Notes | Tinggi | Membuat aplikasi lebih unik |
| Favorite Notes | Tinggi | Simple tapi berguna |
| Dark Mode | Opsional | Bagus, tapi bisa dikerjakan belakangan |
| Reminder | Opsional | Jangan dibuat dulu jika waktu mepet |

---

# Kesimpulan

Konsep terbaik untuk project ini adalah:

> **Noted.: Aplikasi pencatatan akademik berbasis mobile untuk membantu mahasiswa mengelola catatan kuliah berdasarkan mata kuliah, menandai catatan penting, dan mencari catatan dengan cepat.**

Aplikasi ini cukup sederhana untuk dibuat, tetapi tetap terlihat menarik karena memiliki autentikasi, database online, CRUD, search, kategori, favorite, dashboard, MVVM, state management, dan UI lebih dari 5 halaman.
