/*
===========================================================================

Doom 3 BFG Edition GPL Source Code
Copyright (C) 1993-2012 id Software LLC, a ZeniMax Media company.
Copyright (C) 2015-2020 Robert Beckebans
Copyright (C) 2014 Timothy Lottes (AMD)

This file is part of the Doom 3 BFG Edition GPL Source Code ("Doom 3 BFG Edition Source Code").

Doom 3 BFG Edition Source Code is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Doom 3 BFG Edition Source Code is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Doom 3 BFG Edition Source Code.  If not, see <http://www.gnu.org/licenses/>.

In addition, the Doom 3 BFG Edition Source Code is also subject to certain additional terms. You should have received a copy of these additional terms immediately following the terms and conditions of the GNU General Public License which accompanied the Doom 3 BFG Edition Source Code.  If not, please request a copy in writing from id Software at the address below.

If you have questions concerning this license or the applicable additional terms, you may contact in writing id Software LLC, c/o ZeniMax Media Inc., Suite 120, Rockville, Maryland 20850 USA.

===========================================================================
*/

#include "global.inc.hlsl"

// *INDENT-OFF*
uniform sampler2D samp0		: register(s0);
uniform sampler2D samp1		: register(s1); // blue noise 256

struct PS_IN
{
	float4 position : VPOS;
	float2 texcoord0 : TEXCOORD0_centroid;
};

struct PS_OUT
{
	float4 color : COLOR;
};
// *INDENT-ON*

#define USE_CHROMATIC_ABERRATION			0
#define Chromatic_Amount					0.075

#define USE_TECHNICOLOR						0		// [0 or 1]

#define Technicolor_Amount					0.5		// [0.00 to 1.00]
#define Technicolor_Power					4.0		// [0.00 to 8.00]
#define Technicolor_RedNegativeAmount		0.88	// [0.00 to 1.00]
#define Technicolor_GreenNegativeAmount		0.88	// [0.00 to 1.00]
#define Technicolor_BlueNegativeAmount		0.88	// [0.00 to 1.00]

#define USE_VIBRANCE						0
#define Vibrance							0.5	// [-1.00 to 1.00]
#define	Vibrance_RGB_Balance				float3( 1.0, 1.0, 1.0 )

#define USE_DITHERING 						1

float3 overlay( float3 a, float3 b )
{
	//return pow( abs( b ), 2.2 ) < 0.5 ? ( 2.0 * a * b ) : float3( 1.0, 1.0, 1.0 ) - float3( 2.0, 2.0, 2.0 ) * ( float3( 1.0, 1.0, 1.0 ) - a ) * ( 1.0 - b );
	//return abs( b ) < 0.5 ? ( 2.0 * a * b ) : float3( 1.0, 1.0, 1.0 ) - float3( 2.0, 2.0, 2.0 ) * ( float3( 1.0, 1.0, 1.0 ) - a ) * ( 1.0 - b );

	return float3(
			   b.x < 0.5 ? ( 2.0 * a.x * b.x ) : ( 1.0 - 2.0 * ( 1.0 - a.x ) * ( 1.0 - b.x ) ),
			   b.y < 0.5 ? ( 2.0 * a.y * b.y ) : ( 1.0 - 2.0 * ( 1.0 - a.y ) * ( 1.0 - b.y ) ),
			   b.z < 0.5 ? ( 2.0 * a.z * b.z ) : ( 1.0 - 2.0 * ( 1.0 - a.z ) * ( 1.0 - b.z ) ) );
}


void TechnicolorPass( inout float4 color )
{
	const float3 cyanFilter = float3( 0.0, 1.30, 1.0 );
	const float3 magentaFilter = float3( 1.0, 0.0, 1.05 );
	const float3 yellowFilter = float3( 1.6, 1.6, 0.05 );
	const float3 redOrangeFilter = float3( 1.05, 0.62, 0.0 );
	const float3 greenFilter = float3( 0.3, 1.0, 0.0 );

	float2 redNegativeMul   = color.rg * ( 1.0 / ( Technicolor_RedNegativeAmount * Technicolor_Power ) );
	float2 greenNegativeMul = color.rg * ( 1.0 / ( Technicolor_GreenNegativeAmount * Technicolor_Power ) );
	float2 blueNegativeMul  = color.rb * ( 1.0 / ( Technicolor_BlueNegativeAmount * Technicolor_Power ) );

	float redNegative   = dot( redOrangeFilter.rg, redNegativeMul );
	float greenNegative = dot( greenFilter.rg, greenNegativeMul );
	float blueNegative  = dot( magentaFilter.rb, blueNegativeMul );

	float3 redOutput   = float3( redNegative ) + cyanFilter;
	float3 greenOutput = float3( greenNegative ) + magentaFilter;
	float3 blueOutput  = float3( blueNegative ) + yellowFilter;

	float3 result = redOutput * greenOutput * blueOutput;
	color.rgb = lerp( color.rgb, result, Technicolor_Amount );
}


void VibrancePass( inout float4 color )
{
	const float3 vibrance = Vibrance_RGB_Balance * Vibrance;

	float Y = dot( LUMINANCE_SRGB, color );

	float minColor = min( color.r, min( color.g, color.b ) );
	float maxColor = max( color.r, max( color.g, color.b ) );

	float colorSat = maxColor - minColor;

	color.rgb = lerp( float3( Y ), color.rgb, ( 1.0 + ( vibrance * ( 1.0 - ( sign( vibrance ) * colorSat ) ) ) ) );
}


// CHROMATIC ABBERATION

float2 BarrelDistortion( float2 xy, float amount )
{
	float2 cc = xy - 0.5;
	float dist = dot2( cc, cc );

	return xy + cc * dist * amount;
}

float Linterp( float t )
{
	return saturate( 1.0 - abs( 2.0 * t - 1.0 ) );
}

float Remap( float t, float a, float b )
{
	return saturate( ( t - a ) / ( b - a ) );
}

float3 SpectrumOffset( float t )
{
	float lo = step( t, 0.5 );
	float hi = 1.0 - lo;
	float w = Linterp( Remap( t, 1.0 / 6.0, 5.0 / 6.0 ) );
	float3 ret = float3( lo, 1.0, hi ) * float3( 1.0 - w, w, 1.0 - w );

	return pow( ret, float3( 1.0 / 2.2 ) );
}

void ChromaticAberrationPass( inout float4 color )
{
	float amount = Chromatic_Amount; //color.a * 1.0; //rpUser0.x;

	float3 sum = float3( 0.0 );
	float3 sumColor = float3( 0.0 );

	//float samples = rpOverbright.x;
	float samples = 12.0; // * 2;

	for( float i = 0.0; i < samples; i = i + 1.0 )
	{
		//float t = ( ( i / ( samples - 1.0 ) ) - 0.5 );
		float t = ( i / ( samples - 1.0 ) );
		//float t = log( i / ( samples - 1.0 ) );

		float3 so = SpectrumOffset( t );

		sum += so.xyz;
		sumColor += so * tex2D( samp0, BarrelDistortion( fragment.texcoord0, ( 0.5 * amount * t ) ) ).rgb;
	}

	color.rgb = ( sumColor / sum );
	//color.rgb = lerp(color.rgb, (sumColor / sum), Technicolor_Amount);
}



// https://gpuopen.com/vdr-follow-up-fine-art-of-film-grain/

//
// TEMPORAL DITHERING TEST IN LINEAR
//

//
// This is biased (saturates + adds contrast) because dithering done in non-linear space.
//

// Shows proper dithering of a signal (overlapping of dither between bands).
// Results in about a 1-stop improvement in dynamic range over conventional dither
//   which does not overlap dither across bands
//   (try "#define WIDE 0.5" to see the difference below).
//
// This would work a lot better with a proper random number generator (flicker etc is bad).
// Sorry there is a limit to what can be done easily in shadertoy.
//
// Proper dithering algorithm,
//
//   color = floor(color * steps + noise) * (1.0/(steps-1.0))
//
// Where,
//
//   color ... output color {0 to 1}
//   noise ... random number between {-1 to 1}
//   steps ... quantization steps, ie 8-bit = 256
//
// The noise in this case is shaped by a high pass filter.
// This is to produce a better quality temporal dither.

// Scale the width of the dither

//-----------------------------------------------------------------------

float Linear1( float c )
{
	return ( c <= 0.04045 ) ? c / 12.92 : pow( ( c + 0.055 ) / 1.055, 2.4 );
}

float3 Linear3( float3 c )
{
	return float3( Linear1( c.r ), Linear1( c.g ), Linear1( c.b ) );
}

float Srgb1( float c )
{
	return ( c < 0.0031308 ? c * 12.92 : 1.055 * pow( c, 0.41666 ) - 0.055 );
}

float3 Srgb3( float3 c )
{
	return float3( Srgb1( c.r ), Srgb1( c.g ), Srgb1( c.b ) );
}

float3 photoLuma = float3( 0.2126, 0.7152, 0.0722 );
float PhotoLuma( float3 c )
{
	return dot( c, photoLuma );
}



float BlueNoise( float2 n, float x )
{
	float noise = tex2D( samp1, ( n.xy * rpJitterTexOffset.xy ) * 1.0 ).r;

	noise = fract( noise + 0.61803398875 * rpJitterTexOffset.z * x );

	//noise = InterleavedGradientNoise( n );

	noise = RemapNoiseTriErp( noise );

	noise = noise * 2.0 - 1.0;

	return noise;
}

float3 BlueNoise3( float2 n, float x )
{
	float2 uv = n.xy * rpJitterTexOffset.xy;

	float3 noise = tex2D( samp1, uv ).rgb;

	noise = fract( noise + c_goldenRatioConjugate * rpJitterTexOffset.w * x );

	//noise.x = RemapNoiseTriErp( noise.x );
	//noise.y = RemapNoiseTriErp( noise.y );
	//noise.z = RemapNoiseTriErp( noise.z );

	//noise = noise * 2.0 - 1.0;

	return noise;
}


float Noise( float2 n, float x )
{
	n += x;

#if 1
	return fract( sin( dot( n.xy, float2( 12.9898, 78.233 ) ) ) * 43758.5453 ) * 2.0 - 1.0;
#else
	//return BlueNoise( n, 55.0 );
	return BlueNoise( n, 1.0 );

	//return InterleavedGradientNoise( n ) * 2.0 - 1.0;
#endif
}

// Step 1 in generation of the dither source texture.
float Step1( float2 uv, float n )
{
	float a = 1.0, b = 2.0, c = -12.0, t = 1.0;

	return ( 1.0 / ( a * 4.0 + b * 4.0 - c ) ) * (
			   Noise( uv + float2( -1.0, -1.0 ) * t, n ) * a +
			   Noise( uv + float2( 0.0, -1.0 ) * t, n ) * b +
			   Noise( uv + float2( 1.0, -1.0 ) * t, n ) * a +
			   Noise( uv + float2( -1.0, 0.0 ) * t, n ) * b +
			   Noise( uv + float2( 0.0, 0.0 ) * t, n ) * c +
			   Noise( uv + float2( 1.0, 0.0 ) * t, n ) * b +
			   Noise( uv + float2( -1.0, 1.0 ) * t, n ) * a +
			   Noise( uv + float2( 0.0, 1.0 ) * t, n ) * b +
			   Noise( uv + float2( 1.0, 1.0 ) * t, n ) * a +
			   0.0 );
}

// Step 2 in generation of the dither source texture.
float Step2( float2 uv, float n )
{
	float a = 1.0, b = 2.0, c = -2.0, t = 1.0;

	return ( 1.0 / ( a * 4.0 + b * 4.0 - c ) ) * (
			   Step1( uv + float2( -1.0, -1.0 ) * t, n ) * a +
			   Step1( uv + float2( 0.0, -1.0 ) * t, n ) * b +
			   Step1( uv + float2( 1.0, -1.0 ) * t, n ) * a +
			   Step1( uv + float2( -1.0, 0.0 ) * t, n ) * b +
			   Step1( uv + float2( 0.0, 0.0 ) * t, n ) * c +
			   Step1( uv + float2( 1.0, 0.0 ) * t, n ) * b +
			   Step1( uv + float2( -1.0, 1.0 ) * t, n ) * a +
			   Step1( uv + float2( 0.0, 1.0 ) * t, n ) * b +
			   Step1( uv + float2( 1.0, 1.0 ) * t, n ) * a +
			   0.0 );
}

// Used for stills.
float3 Step3( float2 uv )
{
#if 0
	float a = Step2( uv, 0.07 );
	float b = Step2( uv, 0.11 );
	float c = Step2( uv, 0.13 );

	return float3( a, b, c );
#else
	float3 noise = BlueNoise3( uv, 0.0 );

	noise.x = RemapNoiseTriErp( noise.x );
	noise.y = RemapNoiseTriErp( noise.y );
	noise.z = RemapNoiseTriErp( noise.z );

	noise = noise * 2.0 - 1.0;

	return noise;
#endif
}

// Used for temporal dither.
float3 Step3T( float2 uv )
{
#if 0
	float a = Step2( uv, 0.07 * fract( rpJitterTexOffset.z ) );
	float b = Step2( uv, 0.11 * fract( rpJitterTexOffset.z ) );
	float c = Step2( uv, 0.13 * fract( rpJitterTexOffset.z ) );

	return float3( a, b, c );
#else
	float3 noise = BlueNoise3( uv, 1.0 );

	noise.x = RemapNoiseTriErp( noise.x );
	noise.y = RemapNoiseTriErp( noise.y );
	noise.z = RemapNoiseTriErp( noise.z );

	noise = noise * 2.0 - 1.0;

	return noise;
#endif
}


#define STEPS 12.0

void DitheringPass( inout float4 fragColor )
{
	float2 uv = fragment.position.xy * 1.0;
	float2 uv2 = fragment.texcoord0;

	float3 color = fragColor.rgb;

#if 1
// BOTTOM: Show bands.
	if( uv2.y >= 0.975 )
	{
		color = float3( uv2.x );
		color = floor( color * STEPS + Step3( uv ) * 4.0 ) * ( 1.0 / ( STEPS - 1.0 ) );
	}
	else if( uv2.y >= 0.95 )
	{
		color = float3( uv2.x );
		color = floor( color * STEPS ) * ( 1.0 / ( STEPS - 1.0 ) );
	}
	else if( uv2.y >= 0.925 )
	{
		color = float3( uv2.x );
		color = floor( color * STEPS + Step3T( uv ) * 4.0 ) * ( 1.0 / ( STEPS - 1.0 ) );
	}
	// TOP: Show dither texture.
	else if( uv2.y >= 0.9 )
	{
		color = Step3( uv ) * 1.0 + 0.5;
	}
	else
#endif
	{
		color = Linear3( color );

		// Add grain in linear space.
#if 0
		// Slow more correct solutions.
#if 1
		// Too expensive.
		// Helps understand the fast solutions.
		float3 amount = Linear3( Srgb3( color ) + ( 4.0 / STEPS ) ) - color;
#else
		// Less too expensive.
		float luma = PhotoLuma( color );

		// Implement this as a texture lookup table.
		float amount = Linear1( Srgb1( luma ) + ( 4.0 / STEPS ) ) - luma;
#endif

#else
		// Fast solutions.
#if 1
		// Hack 1 (fastest).
		// For HDR need saturate() around luma.
		float luma = PhotoLuma( color );
		float amount = mix(
						   Linear1( 4.0 / STEPS ),
						   Linear1( ( 4.0 / STEPS ) + 1.0 ) - 1.0,
						   luma );
#else
		// Hack 2 (slower?).
		// For HDR need saturate() around color in mix().
		float3 amount = mix(
							float3( Linear1( 4.0 / STEPS ) ),
							float3( Linear1( ( 4.0 / STEPS ) + 1.0 ) - 1.0 ),
							color );
#endif

#endif
		color += Step3T( uv ) * amount;

		// The following represents hardware linear->sRGB xform
		// which happens on sRGB formatted render targets,
		// except using a lot less bits/pixel.
		color = max( float3( 0.0 ), color );
		color = Srgb3( color );
		color = floor( color * STEPS ) * ( 1.0 / ( STEPS - 1.0 ) );
	}

	fragColor.rgb = color;
}



#define ANIMATE_NOISE 1
#define TARGET_BITS 4 // 2^3 = 8 dithered to this many bits
#define DITHER_IN_LINEAR_SPACE 0

//----------------------------------------------------------------------------------------

/*
Items of note!

* The blue noise texture sampling should be set to "nearest" (not mip map!) and repeat

* you should calculate the uv to use based on the pixel coordinate and the size of the blue noise texture.
 * aka you should tile the blue noise texture across the screen.
 * blue noise actually tiles really well unlike white noise.

* A blue noise texture is "low discrepancy over space" which means there are fewer visible patterns than white noise
 * it also gives more even coverage vs white noise. no clumps or voids.

* In an attempt to make it also blue noise over time, you can add the golden ratio and frac it.
 * that makes it lower discrepancy over time, but makes it less good over space.
 * thanks to r4unit for that tip! https://twitter.com/R4_Unit

* Animating the noise in this demo makes the noise basically disappear imo, it's really nice!

For more information:

What the heck is blue nois:
https://blog.demofox.org/2018/01/30/what-the-heck-is-blue-noise/

Low discrepancy sequences:
https://blog.demofox.org/2017/05/29/when-random-numbers-are-too-random-low-discrepancy-sequences/

You can get your own blue noise textures here:
http://momentsingraphics.de/?p=127

*/
void DitheringPassDemoFox( inout float4 fragColor )
{
	// texture color
	float2 uv = fragment.position.xy;
	float2 uv2 = fragment.texcoord0;
	float3 fg = fragColor.rgb;

	float3 color = fg;

#if 1
	// TOP: show bands
	if( uv2.y >= 0.975 )
	{
		color = float3( uv2.x );
		color = floor( color * STEPS + Step3( uv ) * 4.0 ) * ( 1.0 / ( STEPS - 1.0 ) );
	}
	else if( uv2.y >= 0.95 )
	{
		color = float3( uv2.x );
		color = floor( color * STEPS ) * ( 1.0 / ( STEPS - 1.0 ) );
	}
	else if( uv2.y >= 0.925 )
	{
		color = float3( uv2.x );
		color = floor( color * STEPS + Step3T( uv ) * 4.0 ) * ( 1.0 / ( STEPS - 1.0 ) );
	}
	// BOTTOM: show dither texture
	else if( uv2.y >= 0.9 )
	{
		color = Step3( uv ).rgb;
	}
	else
#endif
	{
		// right of the screen is dithered using white noise to a fewer number of bits per color channel
		if( uv2.x > 3.0 / 4.0 )
		{
			// get white noise "random" number
#if ANIMATE_NOISE
			float3 whiteNoise = Hash33( float3( uv, rpJitterTexOffset.w / 256.0 ) );
#else
			float3 whiteNoise = Hash33( float3( uv, 0.0 ) );
#endif

			// dither to the specified number of bits, using sRGB conversions if desired
#if DITHER_IN_LINEAR_SPACE
			fg = pow( fg, float3( 2.2 ) );
#endif

			float scale = exp2( float( TARGET_BITS ) ) - 1.0;
			color = floor( fg * scale + whiteNoise ) / scale;

#if DITHER_IN_LINEAR_SPACE
			color = pow( col, 1.0 / float3( 2.2 ) );
#endif
		}
		// middle right of the screen is dithered using blue noise to a fewer number of bits per color channel
		else if( uv2.x > 2.0 / 4.0 )
		{
			float3 blueNoise = BlueNoise3( uv, 1.0 );

			// dither to the specified number of bits, using sRGB conversions if desired
#if DITHER_IN_LINEAR_SPACE
			fg = pow( fg, float3( 2.2 ) );
#endif

			float scale = exp2( float( TARGET_BITS ) ) - 1.0;
			color = floor( fg * scale + blueNoise ) / scale;

#if DITHER_IN_LINEAR_SPACE
			color = pow( color, 1.0 / float3( 2.2 ) );
#endif
		}
		// middle left of the screen is quantized but not dithered
		else if( uv2.x > 1.0 / 4.0 )
		{
			// dither to the specified number of bits, using sRGB conversions if desired
#if DITHER_IN_LINEAR_SPACE
			fg = pow( fg, float3( 2.2 ) );
#endif

			float scale = exp2( float( TARGET_BITS ) ) - 1.0;
			color = floor( fg * scale + 0.5f ) / scale;

#if DITHER_IN_LINEAR_SPACE
			color = pow( color, 1.0 / float3( 2.2 ) );
#endif
		}
		// left side of screen is left alone for comparison
		else
		{
			color = fg;
		}

		if( abs( uv2.x - 1.0 / 4.0 ) < 0.001 || abs( uv2.x - 2.0 / 4.0 ) < 0.001 || abs( uv2.x - 3.0 / 4.0 ) < 0.001 )
		{
			color = float3( 0.0, 1.0, 0.0 );
		}
	}

	fragColor.rgb = color;
}

void DitheringPassSlim( inout float4 fragColor )
{
	// texture color
	float2 uv = fragment.position.xy;
	float2 uv2 = fragment.texcoord0;
	float3 fg = fragColor.rgb;

	float3 color = fg;

#if 0
	if( uv2.y >= 0.975 )
	{
		// source signal
		color = float3( uv2.x );
	}
	else if( uv2.y >= 0.95 )
	{
		color = float3( uv2.x );

		// quantized signal
		float scale = exp2( float( TARGET_BITS ) ) - 1.0;
		color = floor( color * scale + 0.0f ) / scale;
	}
	else if( uv2.y >= 0.925 )
	{
		// dithered quantized signal
		color = float3( uv2.x );
		color = floor( color * STEPS + Step3T( uv ) * 4.0 ) * ( 1.0 / ( STEPS - 1.0 ) );
	}
	else if( uv2.y >= 0.9 )
	{
		// dither texture
		color = Step3( uv ).rgb;
	}
	else
#endif
	{
		float3 noise = BlueNoise3( uv, 1.0 );

		//noise.x = RemapNoiseTriErp( noise.x );
		//noise.y = RemapNoiseTriErp( noise.y );
		//noise.z = RemapNoiseTriErp( noise.z );

		// dither to the specified number of bits, using sRGB conversions if desired
#if DITHER_IN_LINEAR_SPACE
		fg = pow( fg, float3( 2.2 ) );
#endif

		float scale = exp2( float( TARGET_BITS ) ) - 1.0;
		color = floor( fg * scale + noise ) / scale;

#if DITHER_IN_LINEAR_SPACE
		color = pow( color, 1.0 / float3( 2.2 ) );
#endif
	}

	fragColor.rgb = color;
}


void main( PS_IN fragment, out PS_OUT result )
{
	float2 tCoords = fragment.texcoord0;

	// base color with tone mapping and other post processing applied
	float4 color = tex2D( samp0, tCoords );

#if USE_CHROMATIC_ABERRATION
	ChromaticAberrationPass( color );
#endif

#if USE_TECHNICOLOR
	TechnicolorPass( color );
#endif

#if USE_VIBRANCE
	VibrancePass( color );
#endif

#if USE_DITHERING
	DitheringPassSlim( color );
#endif

	result.color = color;
}
