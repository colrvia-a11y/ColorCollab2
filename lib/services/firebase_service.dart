import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:color_canvas/firestore/firestore_data_schema.dart';
import 'package:color_canvas/data/sample_paints.dart';

class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  // Enable offline persistence (automatically enabled for mobile)
  static Future<void> enableOfflineSupport() async {
    // Firestore automatically enables offline persistence for mobile platforms
    // No additional configuration needed
  }

  // Auth methods
  static User? get currentUser => _auth.currentUser;
  
  // Debug helper to check Firebase configuration
  static Future<Map<String, dynamic>> getFirebaseStatus() async {
    try {
      final user = currentUser;
      final isOnline = await _firestore.doc('test/connection').get().then((_) => true).catchError((_) => false);
      
      return {
        'isAuthenticated': user != null,
        'userId': user?.uid,
        'userEmail': user?.email,
        'isFirestoreOnline': isOnline,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }
  
  static Future<UserCredential> signInWithEmailAndPassword(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }
  
  static Future<UserCredential> createUserWithEmailAndPassword(String email, String password) {
    return _auth.createUserWithEmailAndPassword(email: email, password: password);
  }
  
  static Future<void> signOut() => _auth.signOut();
  
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Admin methods
  static Future<bool> isCurrentUserAdmin() async {
    final user = currentUser;
    if (user == null) return false;
    
    try {
      final idTokenResult = await user.getIdTokenResult();
      return idTokenResult.claims?['admin'] == true;
    } catch (e) {
      // Fallback to Firestore-based admin check
      return await checkAdminStatus(user.uid);
    }
  }

  // Simple admin toggle using Firestore (alternative to Firebase Auth custom claims)
  static Future<bool> checkAdminStatus(String uid) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        return data['isAdmin'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> toggleAdminPrivileges(String uid, bool isAdmin) async {
    final userDocRef = _firestore.collection('users').doc(uid);
    final userDoc = await userDocRef.get();
    
    if (userDoc.exists) {
      // Update existing document
      await userDocRef.update({
        'isAdmin': isAdmin,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Create new user document with admin status
      final user = currentUser;
      if (user != null) {
        final userProfile = UserProfile(
          id: uid,
          email: user.email ?? '',
          displayName: user.displayName ?? 'User',
          plan: 'free',
          paletteCount: 0,
          isAdmin: isAdmin,
          createdAt: DateTime.now(),
        );
        await userDocRef.set(userProfile.toJson());
      }
    }
  }

  // User profile methods
  static Future<void> createUserProfile(UserProfile profile) async {
    await _firestore
        .collection('users')
        .doc(profile.id)
        .set(profile.toJson());
  }

  static Future<UserProfile?> getUserProfile(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    if (!doc.exists) return null;
    return UserProfile.fromJson(doc.data()!, doc.id);
  }

  static Future<void> updateUserProfile(UserProfile profile) async {
    await _firestore
        .collection('users')
        .doc(profile.id)
        .update(profile.toJson());
  }

  // Paint methods
  static Future<List<Paint>> getAllPaints() async {
    try {
      final snapshot = await _firestore.collection('paints').get();
      if (snapshot.docs.isEmpty) {
        // Return sample data if no paints in Firestore
        return await SamplePaints.getSamplePaints();
      }
      return snapshot.docs.map((doc) => Paint.fromJson(doc.data(), doc.id)).toList();
    } catch (e) {
      // Fall back to sample data if Firebase is not configured
      return await SamplePaints.getSamplePaints();
    }
  }

  static Future<List<Paint>> searchPaints(String query) async {
    try {
      final nameQuery = await _firestore
          .collection('paints')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(50)
          .get();
      
      final codeQuery = await _firestore
          .collection('paints')
          .where('code', isGreaterThanOrEqualTo: query)
          .where('code', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(50)
          .get();

      final Set<String> seenIds = {};
      final List<Paint> results = [];
      
      for (final doc in [...nameQuery.docs, ...codeQuery.docs]) {
        if (!seenIds.contains(doc.id)) {
          seenIds.add(doc.id);
          results.add(Paint.fromJson(doc.data(), doc.id));
        }
      }
      
      // If no results from Firestore, search in sample data
      if (results.isEmpty) {
        return await SamplePaints.searchPaints(query);
      }
      
      return results;
    } catch (e) {
      // Fall back to sample data search if Firebase fails
      return await SamplePaints.searchPaints(query);
    }
  }

  static Future<Paint?> getPaintById(String paintId) async {
    final doc = await _firestore.collection('paints').doc(paintId).get();
    if (!doc.exists) return null;
    return Paint.fromJson(doc.data()!, doc.id);
  }

  static Future<List<Paint>> getPaintsByIds(List<String> paintIds) async {
    if (paintIds.isEmpty) return [];
    
    final List<Paint> paints = [];
    
    // Firestore 'in' queries are limited to 10 items
    for (int i = 0; i < paintIds.length; i += 10) {
      final batch = paintIds.skip(i).take(10).toList();
      final snapshot = await _firestore
          .collection('paints')
          .where(FieldPath.documentId, whereIn: batch)
          .get();
      
      paints.addAll(snapshot.docs.map((doc) => Paint.fromJson(doc.data(), doc.id)));
    }
    
    return paints;
  }

  // Brand methods
  static Future<List<Brand>> getAllBrands() async {
    try {
      final snapshot = await _firestore.collection('brands').get();
      if (snapshot.docs.isEmpty) {
        // Return sample data if no brands in Firestore
        return SamplePaints.getSampleBrands();
      }
      return snapshot.docs.map((doc) => Brand.fromJson(doc.data(), doc.id)).toList();
    } catch (e) {
      // Fall back to sample data if Firebase is not configured
      return SamplePaints.getSampleBrands();
    }
  }

  // Palette methods
  static Future<String> createPalette(UserPalette palette) async {
    final user = currentUser;
    if (user == null) throw Exception('User not authenticated');
    
    // Ensure the palette has the correct user ID
    final paletteData = palette.toJson();
    paletteData['userId'] = user.uid; // Ensure userId is set correctly
    
    final docRef = await _firestore
        .collection('palettes')
        .add(paletteData);
    return docRef.id;
  }

  static Future<void> updatePalette(UserPalette palette) async {
    await _firestore
        .collection('palettes')
        .doc(palette.id)
        .update(palette.toJson());
  }

  static Future<void> deletePalette(String paletteId) async {
    await _firestore.collection('palettes').doc(paletteId).delete();
  }

  static Future<List<UserPalette>> getUserPalettes(String userId) async {
    final snapshot = await _firestore
        .collection('palettes')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .get();
    
    return snapshot.docs.map((doc) => UserPalette.fromJson(doc.data(), doc.id)).toList();
  }

  static Future<UserPalette?> getPaletteById(String paletteId) async {
    final doc = await _firestore.collection('palettes').doc(paletteId).get();
    if (!doc.exists) return null;
    return UserPalette.fromJson(doc.data()!, doc.id);
  }

  // Share methods
  static Future<String> createShareLink(ShareLink share) async {
    final docRef = await _firestore
        .collection('shares')
        .add(share.toJson());
    return docRef.id;
  }

  static Future<ShareLink?> getShareLink(String shareId) async {
    final doc = await _firestore.collection('shares').doc(shareId).get();
    if (!doc.exists) return null;
    return ShareLink.fromJson(doc.data()!, doc.id);
  }

  // Import methods for admin
  static Future<void> importPaints(List<Map<String, dynamic>> paintData) async {
    final batch = _firestore.batch();
    
    for (final paint in paintData) {
      final docRef = _firestore.collection('paints').doc();
      batch.set(docRef, paint);
    }
    
    await batch.commit();
  }

  static Future<void> importBrands(List<Map<String, dynamic>> brandData) async {
    final batch = _firestore.batch();
    
    for (final brand in brandData) {
      final docRef = _firestore.collection('brands').doc();
      batch.set(docRef, brand);
    }
    
    await batch.commit();
  }

  // Favorite paint methods
  static Future<void> addFavoritePaint(String paintId) async {
    final user = currentUser;
    if (user == null) throw Exception('User not authenticated');
    
    // Check if already favorited to avoid duplicates
    final existingFavorite = await _firestore
        .collection('favorites')
        .where('userId', isEqualTo: user.uid)
        .where('paintId', isEqualTo: paintId)
        .limit(1)
        .get();
    
    if (existingFavorite.docs.isNotEmpty) {
      throw Exception('Paint is already in favorites');
    }
    
    final favorite = FavoritePaint(
      id: '',
      userId: user.uid,
      paintId: paintId,
      createdAt: DateTime.now(),
    );
    
    await _firestore.collection('favorites').add(favorite.toJson());
  }

  /// Add favorite with denormalized paint data for sample/offline mode
  static Future<void> addFavoritePaintWithData(Paint paint) async {
    final user = currentUser;
    if (user == null) throw Exception('User not authenticated');

    final exists = await _firestore
        .collection('favorites')
        .where('userId', isEqualTo: user.uid)
        .where('paintId', isEqualTo: paint.id)
        .limit(1)
        .get();
    if (exists.docs.isNotEmpty) {
      throw Exception('Paint is already in favorites');
    }

    await _firestore.collection('favorites').add({
      'userId': user.uid,
      'paintId': paint.id,
      'createdAt': Timestamp.fromDate(DateTime.now()),
      'paint': paint.toJson(),
    });
  }
  
  static Future<void> removeFavoritePaint(String paintId) async {
    final userId = currentUser?.uid;
    if (userId == null) throw Exception('User not authenticated');
    
    final query = await _firestore
        .collection('favorites')
        .where('userId', isEqualTo: userId)
        .where('paintId', isEqualTo: paintId)
        .get();
    
    for (final doc in query.docs) {
      await doc.reference.delete();
    }
  }
  
  static Future<List<FavoritePaint>> getUserFavorites(String userId) async {
    final snapshot = await _firestore
        .collection('favorites')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .get();
    
    return snapshot.docs.map((doc) => FavoritePaint.fromJson(doc.data(), doc.id)).toList();
  }
  
  static Future<bool> isPaintFavorited(String paintId) async {
    final userId = currentUser?.uid;
    if (userId == null) return false;
    
    final query = await _firestore
        .collection('favorites')
        .where('userId', isEqualTo: userId)
        .where('paintId', isEqualTo: paintId)
        .limit(1)
        .get();
    
    return query.docs.isNotEmpty;
  }

  static Future<List<Paint>> getUserFavoriteColors(String userId) async {
    final favorites = await getUserFavorites(userId);
    if (favorites.isEmpty) return [];
    
    final paintIds = favorites.map((f) => f.paintId).toList();
    return await getPaintsByIds(paintIds);
  }

  // Stream version for live updates
  static Stream<List<Paint>> streamUserFavoriteColors(String userId) {
    return _firestore
        .collection('favorites')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          if (snapshot.docs.isEmpty) return <Paint>[];

          final List<Paint> resolved = [];
          final List<String> idsToFetch = [];

          // First pass: use embedded data when present; queue missing IDs
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final hasEmbedded = data['paint'] is Map<String, dynamic>;
            if (hasEmbedded) {
              final map = Map<String, dynamic>.from(data['paint']);
              final String id = (data['paintId'] as String?) ?? doc.id;
              resolved.add(Paint.fromJson(map, id));
            } else {
              final id = (data['paintId'] as String? ?? '').trim();
              if (id.isNotEmpty) idsToFetch.add(id);
            }
          }

          // Second pass: fetch any that need lookup by ID
          if (idsToFetch.isNotEmpty) {
            final fetched = await getPaintsByIds(idsToFetch);
            // Append fetched paints to the result (order already set by favorites)
            resolved.addAll(fetched);
          }

          return resolved;
        });
  }

  // Copied paint methods
  static Future<void> addCopiedPaint(Paint paint) async {
    final userId = currentUser?.uid;
    if (userId == null) throw Exception('User not authenticated');
    
    final copied = CopiedPaint(
      id: '',
      userId: userId,
      paint: paint,
      createdAt: DateTime.now(),
    );
    
    await _firestore.collection('copied_paints').add(copied.toJson());
  }
  
  static Future<List<CopiedPaint>> getUserCopiedPaints(String userId) async {
    final snapshot = await _firestore
        .collection('copied_paints')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    
    return snapshot.docs.map((doc) => CopiedPaint.fromJson(doc.data(), doc.id)).toList();
  }

  // Brand filtering methods
  static Future<List<Paint>> getPaintsByBrands(List<String> brandIds) async {
    if (brandIds.isEmpty) return getAllPaints();
    
    final List<Paint> paints = [];
    
    // Firestore 'in' queries are limited to 10 items
    for (int i = 0; i < brandIds.length; i += 10) {
      final batch = brandIds.skip(i).take(10).toList();
      final snapshot = await _firestore
          .collection('paints')
          .where('brandId', whereIn: batch)
          .get();
      
      paints.addAll(snapshot.docs.map((doc) => Paint.fromJson(doc.data(), doc.id)));
    }
    
    return paints;
  }

  // Storage methods
  static Future<String> uploadPaletteImage(String paletteId, List<int> imageBytes) async {
    final String userId = currentUser?.uid ?? 'anonymous';
    final String path = 'exports/$userId/$paletteId/palette.png';
    
    final ref = _storage.ref().child(path);
    await ref.putData(Uint8List.fromList(imageBytes));
    
    return await ref.getDownloadURL();
  }

  // Palettes: get most recent saved palette for current user
  static Future<UserPalette?> getMostRecentUserPalette() async {
    final user = currentUser;
    if (user == null) return null;
    final snap = await _firestore
      .collection('palettes')
      .where('userId', isEqualTo: user.uid)
      .orderBy('createdAt', descending: true)
      .limit(1)
      .get();
    if (snap.docs.isEmpty) return null;
    return UserPalette.fromJson(snap.docs.first.data(), snap.docs.first.id);
  }

  // Visualizer save/load
  static Future<String> saveVisualizerScene(VisualizerDoc doc) async {
    if (doc.id.isEmpty) {
      final ref = _firestore.collection('visualizations').doc();
      await ref.set(doc.toJson());
      return ref.id;
    } else {
      final ref = _firestore.collection('visualizations').doc(doc.id);
      await ref.set(doc.toJson());
      return doc.id;
    }
  }

  static Future<VisualizerDoc?> getVisualizerScene(String id) async {
    final ref = await _firestore.collection('visualizations').doc(id).get();
    if (!ref.exists) return null;
    return VisualizerDoc.fromJson(ref.data()!, ref.id);
  }

  // Color Stories methods
  static Future<List<ColorStory>> getColorStories({
    List<String>? themes,
    List<String>? families, 
    List<String>? rooms,
    bool? isFeatured,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    Query q = _firestore.collection('colorStories');

    // Pick ONE array-contains-any on the largest selected group
    final selections = <String, List<String>>{};
    if (themes != null && themes.isNotEmpty) selections['themes'] = themes;
    if (families != null && families.isNotEmpty) selections['families'] = families;
    if (rooms != null && rooms.isNotEmpty) selections['rooms'] = rooms;
    if (selections.isNotEmpty) {
      final sorted = selections.entries.toList()
        ..sort((a,b) => b.value.length.compareTo(a.value.length));
      final serverField = sorted.first.key;
      final serverValues = sorted.first.value.take(10).toList();
      q = q.where(serverField, arrayContainsAny: serverValues);
    }

    if (isFeatured != null) q = q.where('isFeatured', isEqualTo: isFeatured);
    q = q.orderBy('isFeatured', descending: true).orderBy('createdAt', descending: true);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    final snap = await q.limit(limit).get();

    // Parse
    var stories = snap.docs
        .map((d) => ColorStory.fromJson(d.data() as Map<String, dynamic>, d.id))
        .toList();

    // Client-side AND across the other groups
    bool matches(ColorStory s) {
      bool ok = true;
      if (themes != null && themes.isNotEmpty)   ok &= s.themes.any(themes.contains);
      if (families != null && families.isNotEmpty) ok &= s.families.any(families.contains);
      if (rooms != null && rooms.isNotEmpty)     ok &= s.rooms.any(rooms.contains);
      return ok;
    }
    if (selections.length > 1) stories = stories.where(matches).toList();
    return stories;
  }

  /// Gets Color Stories with pagination metadata for cursor-based loading
  static Future<Map<String, dynamic>> getColorStoriesWithCursor({
    List<String>? themes,
    List<String>? families, 
    List<String>? rooms,
    bool? isFeatured,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    Query q = _firestore.collection('colorStories');

    // Pick ONE array-contains-any on the largest selected group
    final selections = <String, List<String>>{};
    if (themes != null && themes.isNotEmpty) selections['themes'] = themes;
    if (families != null && families.isNotEmpty) selections['families'] = families;
    if (rooms != null && rooms.isNotEmpty) selections['rooms'] = rooms;
    if (selections.isNotEmpty) {
      final sorted = selections.entries.toList()
        ..sort((a,b) => b.value.length.compareTo(a.value.length));
      final serverField = sorted.first.key;
      final serverValues = sorted.first.value.take(10).toList();
      q = q.where(serverField, arrayContainsAny: serverValues);
    }

    if (isFeatured != null) q = q.where('isFeatured', isEqualTo: isFeatured);
    q = q.orderBy('isFeatured', descending: true).orderBy('createdAt', descending: true);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    final snap = await q.limit(limit).get();

    // Parse
    var stories = snap.docs
        .map((d) => ColorStory.fromJson(d.data() as Map<String, dynamic>, d.id))
        .toList();
    
    // Store original docs for cursor tracking
    final originalDocs = snap.docs;

    // Client-side AND across the other groups
    bool matches(ColorStory s) {
      bool ok = true;
      if (themes != null && themes.isNotEmpty)   ok &= s.themes.any(themes.contains);
      if (families != null && families.isNotEmpty) ok &= s.families.any(families.contains);
      if (rooms != null && rooms.isNotEmpty)     ok &= s.rooms.any(rooms.contains);
      return ok;
    }
    
    if (selections.length > 1) {
      final filteredData = <Map<String, dynamic>>[];
      stories = stories.where((story) {
        if (matches(story)) {
          // Find corresponding document for this story
          final doc = originalDocs.firstWhere((d) => d.id == story.id);
          filteredData.add({'story': story, 'doc': doc});
          return true;
        }
        return false;
      }).toList();
      
      return {
        'stories': stories,
        'lastDocument': filteredData.isNotEmpty ? filteredData.last['doc'] : null,
        'hasMore': originalDocs.length >= limit && stories.length >= limit,
      };
    }
    
    return {
      'stories': stories,
      'lastDocument': originalDocs.isNotEmpty ? originalDocs.last : null,
      'hasMore': originalDocs.length >= limit,
    };
  }

  static Future<ColorStory?> getColorStoryById(String id) async {
    final doc = await _firestore.collection('colorStories').doc(id).get();
    if (!doc.exists) return null;
    return ColorStory.fromJson(doc.data()!, doc.id);
  }

  static Future<ColorStory?> getColorStoryBySlug(String slug) async {
    final snapshot = await _firestore
        .collection('colorStories')
        .where('slug', isEqualTo: slug)
        .limit(1)
        .get();
    
    if (snapshot.docs.isEmpty) return null;
    return ColorStory.fromJson(snapshot.docs.first.data(), snapshot.docs.first.id);
  }

  static Stream<List<ColorStory>> streamFeaturedColorStories({int limit = 10}) {
    return _firestore
        .collection('colorStories')
        .where('isFeatured', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => ColorStory.fromJson(doc.data(), doc.id)).toList());
  }

  static Stream<List<ColorStory>> streamAllColorStories({int limit = 20}) {
    return _firestore
        .collection('colorStories')
        .orderBy('isFeatured', descending: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => ColorStory.fromJson(doc.data(), doc.id)).toList());
  }

  // Admin methods for managing Color Stories
  static Future<DocumentReference> createColorStory(ColorStory story) async {
    final ref = _firestore.collection('colorStories').doc();
    final storyWithTimestamps = story.copyWith(
      id: ref.id,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await ref.set(storyWithTimestamps.toJson());
    return ref;
  }

  static Future<void> updateColorStory(ColorStory story) async {
    final storyWithUpdatedTime = story.copyWith(updatedAt: DateTime.now());
    await _firestore.collection('colorStories').doc(story.id).update(storyWithUpdatedTime.toJson());
  }

  static Future<void> deleteColorStory(String id) async {
    await _firestore.collection('colorStories').doc(id).delete();
  }

  // Taxonomy methods
  static Future<Map<String, List<String>>> getTaxonomyOptions() async {
    try {
      final doc = await _firestore.collection('appConfig').doc('taxonomies').get();
      
      if (!doc.exists) {
        // Return default taxonomies if document doesn't exist
        return _getDefaultTaxonomies();
      }
      
      final data = doc.data()!;
      return {
        'themes': List<String>.from(data['themesOptions'] ?? _getDefaultTaxonomies()['themes']!),
        'families': List<String>.from(data['familiesOptions'] ?? _getDefaultTaxonomies()['families']!),
        'rooms': List<String>.from(data['roomsOptions'] ?? _getDefaultTaxonomies()['rooms']!),
      };
    } catch (e) {
      // Fallback to defaults on error
      return _getDefaultTaxonomies();
    }
  }
  
  static Map<String, List<String>> _getDefaultTaxonomies() {
    return {
      'themes': [
        'coastal', 'modern-farmhouse', 'traditional', 'contemporary', 'rustic', 
        'minimalist', 'industrial', 'bohemian', 'scandinavian', 'mid-century',
        'urban', 'vintage', 'eclectic', 'art-deco'
      ],
      'families': [
        'greens', 'blues', 'neutrals', 'warm-neutrals', 'cool-neutrals', 
        'whites', 'grays', 'earth-tones', 'warm-colors', 'cool-colors',
        'pastels', 'bold-colors', 'monochrome', 'jewel-tones', 'natural-colors'
      ],
      'rooms': [
        'kitchen', 'living', 'bedroom', 'bathroom', 'dining', 'exterior', 
        'office', 'nursery', 'hallway', 'entryway', 'laundry', 'basement',
        'attic', 'garage', 'patio', 'deck', 'garden', 'whole-home'
      ],
    };
  }
  
  static Future<void> updateTaxonomyOptions({
    List<String>? themes,
    List<String>? families,
    List<String>? rooms,
  }) async {
    final docRef = _firestore.collection('appConfig').doc('taxonomies');
    
    final updates = <String, dynamic>{};
    if (themes != null) updates['themesOptions'] = themes;
    if (families != null) updates['familiesOptions'] = families;
    if (rooms != null) updates['roomsOptions'] = rooms;
    updates['updatedAt'] = FieldValue.serverTimestamp();
    
    await docRef.set(updates, SetOptions(merge: true));
  }
  
  static Future<void> initializeTaxonomies() async {
    final docRef = _firestore.collection('appConfig').doc('taxonomies');
    final doc = await docRef.get();
    
    if (!doc.exists) {
      final defaultTaxonomies = _getDefaultTaxonomies();
      await docRef.set({
        'themesOptions': defaultTaxonomies['themes'],
        'familiesOptions': defaultTaxonomies['families'], 
        'roomsOptions': defaultTaxonomies['rooms'],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// One-time admin maintenance: Backfill facets field on existing Color Stories
  /// This method is idempotent and safe to run multiple times
  static Future<Map<String, dynamic>> backfillColorStoryFacets() async {
    try {
      int processedCount = 0;
      int updatedCount = 0;
      int errorCount = 0;
      final List<String> errors = [];
      
      // Get all color stories in batches to avoid memory issues
      Query query = _firestore.collection('colorStories');
      QuerySnapshot snapshot = await query.get();
      
      final batch = _firestore.batch();
      int batchCount = 0;
      const int maxBatchSize = 500; // Firestore batch limit
      
      for (final doc in snapshot.docs) {
        try {
          processedCount++;
          final data = doc.data() as Map<String, dynamic>;
          final existingFacets = data['facets'] as List<dynamic>?;
          
          // Skip if facets already exist and are non-empty (idempotent)
          if (existingFacets != null && existingFacets.isNotEmpty) {
            continue;
          }
          
          // Build facets from existing themes, families, and rooms
          final themes = List<String>.from(data['themes'] ?? []);
          final families = List<String>.from(data['families'] ?? []);
          final rooms = List<String>.from(data['rooms'] ?? []);
          
          final facets = ColorStory.buildFacets(
            themes: themes,
            families: families,
            rooms: rooms,
          );
          
          // Add update to batch
          batch.update(doc.reference, {'facets': facets});
          batchCount++;
          updatedCount++;
          
          // Commit batch if it reaches max size
          if (batchCount >= maxBatchSize) {
            await batch.commit();
            batchCount = 0;
          }
          
        } catch (e) {
          errorCount++;
          errors.add('Doc ${doc.id}: $e');
        }
      }
      
      // Commit remaining batch operations
      if (batchCount > 0) {
        await batch.commit();
      }
      
      return {
        'success': true,
        'processedCount': processedCount,
        'updatedCount': updatedCount,
        'errorCount': errorCount,
        'errors': errors,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Get all Color Stories for maintenance operations (no pagination)
  /// WARNING: This loads all stories into memory - use only for admin maintenance
  static Future<List<ColorStory>> getAllColorStoriesForMaintenance() async {
    try {
      final snapshot = await _firestore.collection('colorStories').get();
      final stories = <ColorStory>[];
      
      for (final doc in snapshot.docs) {
        try {
          final story = ColorStory.fromJson(doc.data(), doc.id);
          stories.add(story);
        } catch (e) {
          // Skip malformed documents but continue processing
          debugPrint('Error parsing Color Story ${doc.id}: $e');
        }
      }
      
      return stories;
    } catch (e) {
      throw Exception('Failed to load Color Stories for maintenance: $e');
    }
  }
}