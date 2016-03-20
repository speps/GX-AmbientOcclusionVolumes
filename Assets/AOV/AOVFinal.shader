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
			#pragma vertex vert_img
			#pragma fragment frag
			#include "UnityCG.cginc"
		
			sampler2D _MainTex;
			sampler2D _AccessibilityTex;
			float _DebugMix;
 
			fixed4 frag(v2f_img i) : COLOR
			{
				fixed4 base = tex2D(_MainTex, i.uv);
				fixed4 ao = tex2D(_AccessibilityTex, i.uv);
				return lerp(float4(1,1,1,1), base, _DebugMix) * (1 - ao);
			}
			ENDCG
		}
	}
}
