import {View} from 'react-native'
import {Trans} from '@lingui/react/macro'

import {atoms as a, useTheme} from '#/alf'
import {Mark as Logo} from '#/components/icons/Logo'
import {Text} from '#/components/Typography'

/**
 * Empty-state placeholder shown beneath a post that has no replies yet.
 */
export function ThreadEmptyReplies({height}: {height?: number}) {
  const t = useTheme()

  return (
    <View
      testID="threadEmptyReplies"
      style={[
        a.w_full,
        a.align_center,
        a.justify_center,
        a.px_lg,
        {minHeight: height ?? 280},
      ]}>
      <Logo size="4xl" fill={t.atoms.text_contrast_low.color} />
      <Text
        style={[
          a.pt_md,
          a.text_md,
          a.font_medium,
          a.leading_snug,
          a.text_center,
          t.atoms.text_contrast_low,
        ]}>
        <Trans>You can be first to comment</Trans>
      </Text>
    </View>
  )
}
