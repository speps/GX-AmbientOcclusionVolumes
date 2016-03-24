Shader "Hidden/AOVFinal"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
		_AccessibilityTex ("Texture", 2D) = "white" {}
		_DebugMix ("Debug Mix", Range (0,1)) = 1
	}
	SubShader
	{
		Pass
		{
			ZTest Always

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"
		
			sampler2D _MainTex;
			uniform float2 _MainTex_TexelSize;
			sampler2D _AccessibilityTex;
			float _DebugMix;

			struct v2f {
				float4 vertex : SV_POSITION;
				float2 uvMain : TEXCOORD0;
				float2 uvAOV : TEXCOORD1;
			};

			v2f vert (appdata_img v)
			{
				v2f o;
				o.vertex = mul(UNITY_MATRIX_MVP, v.vertex);
				o.uvMain = v.texcoord.xy;
				o.uvAOV = v.texcoord.xy;
				#if UNITY_UV_STARTS_AT_TOP
				if (_MainTex_TexelSize.y < 0)
					o.uvAOV.y = 1 - o.uvAOV.y;
				#endif
				return o;
			}
 
			fixed4 frag(v2f i) : COLOR
			{
				fixed4 base = tex2D(_MainTex, i.uvMain);
				fixed4 ao = tex2D(_AccessibilityTex, i.uvAOV).xxxx;
				return lerp(float4(1,1,1,1), base, _DebugMix) * (1 - ao);
			}
			ENDCG
		}
	}
}
